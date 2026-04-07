import Foundation

/// AgentBackend that receives state updates from Claude Code hooks via HookServer.
/// Provides instant, accurate state detection with zero false positives.
final class ClaudeCodeHookBackend: AgentBackend, @unchecked Sendable {
    let name = "Claude Code"
    let iconName = "terminal"

    /// Sessions tracked via hook events. Key = sessionId.
    /// Access serialized through the syncQueue.
    private var trackedSessions: [String: TrackedSession] = [:]
    private let syncQueue = DispatchQueue(label: "hook-backend-sync")

    struct TrackedSession {
        let id: String
        var pid: Int32
        let cwd: String
        let startedAt: Date
        var state: SessionState
        var lastActivity: Date
    }

    /// Called by the HookServer when a hook event arrives.
    func handleEvent(_ event: HookEvent) {
        syncQueue.sync {
            _handleEvent(event)
        }
    }

    private func _handleEvent(_ event: HookEvent) {

        let sessionId = event.sessionId
        let state = mapEventToState(event)

        if var session = trackedSessions[sessionId] {
            session.state = state
            session.lastActivity = Date()
            trackedSessions[sessionId] = session
        } else if event.eventName == "SessionStart" || !sessionId.isEmpty {
            // New session discovered via hook
            trackedSessions[sessionId] = TrackedSession(
                id: sessionId,
                pid: findPidForSession(sessionId),
                cwd: event.cwd,
                startedAt: Date(),
                state: state,
                lastActivity: Date()
            )
        }
    }

    private func mapEventToState(_ event: HookEvent) -> SessionState {
        switch event.eventName {
        case "SessionStart", "UserPromptSubmit":
            return .active
        case "Stop":
            return .waitingForInput
        case "PermissionRequest":
            return .permissionRequest(event.toolName ?? "tool")
        case "Notification":
            if event.notificationType == "elicitation_dialog" {
                return .waitingForInput
            }
            return .active
        default:
            return .active
        }
    }

    /// Try to find the PID for a session by scanning ~/.claude/sessions/
    private func findPidForSession(_ sessionId: String) -> Int32 {
        let sessionsDir = NSHomeDirectory() + "/.claude/sessions"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: sessionsDir) else {
            return 0
        }
        for file in files where file.hasSuffix(".json") {
            let path = (sessionsDir as NSString).appendingPathComponent(file)
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sid = json["sessionId"] as? String,
                  sid == sessionId,
                  let pid = json["pid"] as? Int
            else { continue }
            return Int32(pid)
        }
        return 0
    }

    // MARK: - AgentBackend

    func discoverSessions() async throws -> [DiscoveredSession] {
        let sessions = syncQueue.sync { Array(trackedSessions.values) }

        return sessions.compactMap { tracked in
            guard ProcessProbe.isAlive(pid: tracked.pid) || tracked.pid == 0 else {
                return nil
            }
            return DiscoveredSession(
                id: tracked.id,
                pid: tracked.pid,
                cwd: tracked.cwd,
                startedAt: tracked.startedAt,
                backendName: name,
                iconName: iconName,
                metadata: ["source": "hooks"]
            )
        }
    }

    func analyzeState(for session: DiscoveredSession) async throws -> SessionState {
        let state = syncQueue.sync { trackedSessions[session.id]?.state ?? .idle }
        return state
    }

    func watchPath(for session: DiscoveredSession) -> String? {
        nil // Push-based, no file watching needed
    }

    func isAlive(session: DiscoveredSession) -> Bool {
        session.pid == 0 || ProcessProbe.isAlive(pid: session.pid)
    }

    /// Remove dead sessions.
    func pruneDeadSessions() {
        syncQueue.sync {
            trackedSessions = trackedSessions.filter { _, session in
                session.pid == 0 || ProcessProbe.isAlive(pid: session.pid)
            }
        }
    }
}
