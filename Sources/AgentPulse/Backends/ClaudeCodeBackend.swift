import Foundation

final class ClaudeCodeBackend: AgentBackend, @unchecked Sendable {
    let name = "Claude Code"
    let iconName = "terminal"

    private let sessionsDirectory: String
    private let projectsDirectory: String

    /// If a tool_use is the last entry and older than this, the session needs attention.
    /// Set low (1s) because the file write + kqueue notification already adds ~1s latency.
    var attentionThresholdSeconds: TimeInterval = 1.0

    /// Tools that represent the agent asking the user something.
    private let userFacingTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// Tools that are inherently long-running and should not trigger "needs approval".
    private let longRunningTools: Set<String> = ["Agent", "Skill"]

    init(
        sessionsDirectory: String = NSHomeDirectory() + "/.claude/sessions",
        projectsDirectory: String = NSHomeDirectory() + "/.claude/projects"
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.projectsDirectory = projectsDirectory
    }

    // MARK: - Discovery

    func discoverSessions() async throws -> [DiscoveredSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsDirectory) else {
            return []
        }

        var sessions: [DiscoveredSession] = []
        for file in files where file.hasSuffix(".json") {
            guard let session = parseSessionFile(file) else { continue }
            sessions.append(session)
        }
        return sessions
    }

    func analyzeState(for session: DiscoveredSession) async throws -> SessionState {
        guard let jsonlPath = session.metadata["jsonlPath"] else {
            return .idle
        }

        let entries = readLastEntries(from: jsonlPath, count: 10)
        if entries.isEmpty { return .idle }

        return analyzeEntries(entries)
    }

    func watchPath(for session: DiscoveredSession) -> String? {
        session.metadata["jsonlPath"]
    }

    func isAlive(session: DiscoveredSession) -> Bool {
        ProcessProbe.isAlive(pid: session.pid)
    }

    // MARK: - Session File Parsing

    private func parseSessionFile(_ filename: String) -> DiscoveredSession? {
        let path = (sessionsDirectory as NSString).appendingPathComponent(filename)
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String,
              let startedAtMs = json["startedAt"] as? Double
        else { return nil }

        let pid32 = Int32(pid)
        guard ProcessProbe.isAlive(pid: pid32) else { return nil }

        let jsonlPath = deriveJSONLPath(cwd: cwd, sessionId: sessionId)

        return DiscoveredSession(
            id: sessionId,
            pid: pid32,
            cwd: cwd,
            startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
            backendName: name,
            iconName: iconName,
            metadata: ["jsonlPath": jsonlPath]
        )
    }

    func deriveJSONLPath(cwd: String, sessionId: String) -> String {
        let encoded = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(projectsDirectory)/\(encoded)/\(sessionId).jsonl"
    }

    // MARK: - JSONL Parsing

    func readLastEntries(from path: String, count: Int) -> [JSONLEntry] {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fileHandle.close() }

        let fileSize = fileHandle.seekToEndOfFile()
        let readSize: UInt64 = min(fileSize, 64 * 1024) // 64KB to cover more entries
        let offset = fileSize - readSize
        fileHandle.seek(toFileOffset: offset)

        guard let data = fileHandle.availableData as Data?,
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        let lines = text.components(separatedBy: "\n")
            .filter { !$0.isEmpty }

        let lastLines = Array(lines.suffix(count))
        return lastLines.compactMap { parseJSONLLine($0) }
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func parseJSONLLine(_ line: String) -> JSONLEntry? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else { return nil }

        let subtype = json["subtype"] as? String
        let timestamp = (json["timestamp"] as? String).flatMap {
            Self.timestampFormatter.date(from: $0)
        }
        let uuid = json["uuid"] as? String ?? ""

        var stopReason: String?
        var contentTypes: [String] = []
        var toolName: String?

        if let message = json["message"] as? [String: Any] {
            stopReason = message["stop_reason"] as? String
            if let content = message["content"] as? [[String: Any]] {
                contentTypes = content.compactMap { $0["type"] as? String }
                if let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }) {
                    toolName = toolUse["name"] as? String
                }
            }
        }

        return JSONLEntry(
            type: type,
            subtype: subtype,
            uuid: uuid,
            timestamp: timestamp,
            stopReason: stopReason,
            contentTypes: contentTypes,
            toolName: toolName
        )
    }

    // MARK: - State Analysis

    /// Analyze JSONL entries to determine the session state.
    ///
    /// The JSONL event patterns are:
    ///
    /// **Active (tools auto-approved, results flowing):**
    ///   assistant stop=tool_use  tools=[Bash]
    ///   user      tool_result                   ← appears within seconds
    ///
    /// **Waiting for input (turn ended):**
    ///   assistant stop=end_turn  content=[text]
    ///   system    sub=turn_duration             ← explicit turn-end marker
    ///
    /// **Waiting for user response (AskUserQuestion or permission):**
    ///   assistant stop=tool_use  tools=[AskUserQuestion]
    ///   ... long gap, no tool_result ...        ← user is reading/deciding
    ///
    func analyzeEntries(_ entries: [JSONLEntry]) -> SessionState {
        // Skip non-meaningful entries (file-history-snapshot, queue-operation, etc.)
        let meaningful = entries.filter {
            $0.type == "user" || $0.type == "assistant" || ($0.type == "system" && $0.subtype == "turn_duration")
        }
        guard let last = meaningful.last else { return .idle }

        // Debug: log what we're analyzing
        let elapsed = last.timestamp.map { String(format: "%.1fs ago", Date().timeIntervalSince($0)) } ?? "no-ts"
        logDebug("analyzeEntries: last=\(last.type) stop=\(last.stopReason ?? "nil") tool=\(last.toolName ?? "nil") \(elapsed)", category: .state)

        // 1. turn_duration → turn ended, waiting for next user message
        if last.type == "system" && last.subtype == "turn_duration" {
            return .waitingForInput
        }

        // 2. assistant with end_turn or stop_sequence → finished speaking, waiting for user
        if last.type == "assistant" && (last.stopReason == "end_turn" || last.stopReason == "stop_sequence") {
            return .waitingForInput
        }

        // 3. user message with tool_result → tool just ran, agent is processing result
        if last.type == "user" && last.contentTypes.contains("tool_result") {
            return .active
        }

        // 4. user message with no content types → user just sent a new message, agent working
        if last.type == "user" && last.contentTypes.isEmpty {
            return .active
        }

        // 5. user message with text → user sent follow-up text, agent working
        if last.type == "user" {
            return .active
        }

        // 6. assistant with tool_use as LAST entry → either:
        //    a) Tool is running and result hasn't been written yet (active)
        //    b) Waiting for user (AskUserQuestion, ExitPlanMode)
        //    c) Long-running tool (Agent, Skill) — stays active
        //    d) Permission prompt — needs approval
        //    Distinguish by tool name and elapsed time.
        if last.type == "assistant" && (last.stopReason == "tool_use" || last.contentTypes.contains("tool_use")) {
            if let ts = last.timestamp {
                let elapsed = Date().timeIntervalSince(ts)
                if elapsed > attentionThresholdSeconds {
                    if let tool = last.toolName, userFacingTools.contains(tool) {
                        return .waitingForInput
                    }
                    if let tool = last.toolName, longRunningTools.contains(tool) {
                        return .active
                    }
                    return .permissionRequest(last.toolName ?? "tool")
                }
            }
            // Tool just dispatched, result coming soon
            return .active
        }

        // 7. assistant with text only, no stop_reason → still streaming (if recent)
        if last.type == "assistant" && last.stopReason == nil {
            if let ts = last.timestamp, Date().timeIntervalSince(ts) < 60 {
                return .active
            }
            return .idle
        }

        // 8. Fallback: check recency
        if let ts = last.timestamp, Date().timeIntervalSince(ts) < 60 {
            return .active
        }

        return .idle
    }
}

/// A parsed JSONL entry with just the fields we need for state analysis.
struct JSONLEntry: Sendable {
    let type: String            // "user", "assistant", "system"
    let subtype: String?        // "turn_duration", etc.
    let uuid: String
    let timestamp: Date?
    let stopReason: String?     // "end_turn", "tool_use", etc.
    let contentTypes: [String]  // ["text"], ["tool_use"], ["tool_result"], etc.
    let toolName: String?       // "Bash", "Write", "AskUserQuestion", etc.
}
