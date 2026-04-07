import Foundation
import SwiftUI

/// Simple file logger for debugging — writes to /tmp/agentpulse.log
func logDebug(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    let path = "/tmp/agentpulse.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

/// Central store that discovers and monitors agent sessions across all backends.
@Observable
@MainActor
final class SessionStore {
    let backends: [AgentBackend]
    var sessions: [AgentSession] = []

    private var monitors: [String: SessionMonitor] = [:]
    private var discoveryTimer: Timer?
    private let discoveryInterval: TimeInterval = 3.0
    var onAttentionNeeded: ((AgentSession) -> Void)?

    init(backends: [AgentBackend]) {
        self.backends = backends
    }

    func startMonitoring() {
        // Initial discovery
        Task { await refresh() }

        // Periodic discovery
        discoveryTimer = Timer.scheduledTimer(
            withTimeInterval: discoveryInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh()
            }
        }
    }

    func stopMonitoring() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        for monitor in monitors.values {
            monitor.stop()
        }
        monitors.removeAll()
        sessions.removeAll()
    }

    func refresh() async {
        var allDiscovered: [(DiscoveredSession, AgentBackend)] = []

        for backend in backends {
            if let discovered = try? await backend.discoverSessions() {
                logDebug("Discovered \(discovered.count) sessions from \(backend.name)")
                for session in discovered {
                    allDiscovered.append((session, backend))
                }
            }
        }

        let discoveredIds = Set(allDiscovered.map(\.0.id))

        // Remove sessions that no longer exist
        let removedIds = Set(sessions.map(\.id)).subtracting(discoveredIds)
        for id in removedIds {
            monitors[id]?.stop()
            monitors.removeValue(forKey: id)
        }
        sessions.removeAll { removedIds.contains($0.id) }

        // Add new sessions and start monitors
        for (discovered, backend) in allDiscovered {
            if sessions.contains(where: { $0.id == discovered.id }) {
                continue
            }

            let agentSession = AgentSession(from: discovered)
            sessions.append(agentSession)

            let monitor = SessionMonitor(
                session: discovered,
                backend: backend
            ) { [weak self] newState in
                Task { @MainActor [weak self] in
                    self?.updateState(sessionId: discovered.id, state: newState)
                }
            }
            monitors[discovered.id] = monitor
            monitor.start()
        }
    }

    private func updateState(sessionId: String, state: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }

        let previousState = sessions[index].state
        sessions[index].state = state
        sessions[index].lastActivity = Date()

        logDebug("[AgentPulse] Session \(sessions[index].projectName): \(previousState.label) → \(state.label)")

        // Notify if attention is newly needed
        if state.isAttentionNeeded && !previousState.isAttentionNeeded {
            logDebug("[AgentPulse] Firing notification for \(sessions[index].projectName)")
            onAttentionNeeded?(sessions[index])
        }

        // Remove dead sessions after a short delay
        if state == .dead {
            let id = sessionId
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                self.sessions.removeAll { $0.id == id }
                self.monitors[id]?.stop()
                self.monitors.removeValue(forKey: id)
            }
        }
    }
}
