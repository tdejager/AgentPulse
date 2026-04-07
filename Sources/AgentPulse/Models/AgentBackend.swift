import Foundation

/// Protocol that each agent implementation conforms to.
/// Adding a new agent = one new file implementing this protocol.
protocol AgentBackend: AnyObject, Sendable {
    /// Human-readable name (e.g. "Claude Code")
    var name: String { get }

    /// SF Symbol icon name for the UI
    var iconName: String { get }

    /// Discover currently active sessions.
    /// Called on a timer by SessionStore (every ~3s).
    func discoverSessions() async throws -> [DiscoveredSession]

    /// Analyze the current state of a known session.
    /// Called when the watched file changes (kqueue event) or on periodic poll.
    func analyzeState(for session: DiscoveredSession) async throws -> SessionState

    /// Return the file path to watch for live state changes (JSONL, etc.).
    /// SessionMonitor uses this to set up DispatchSource monitoring.
    func watchPath(for session: DiscoveredSession) -> String?

    /// Check if the session's process is still alive.
    func isAlive(session: DiscoveredSession) -> Bool
}

/// Raw session info returned by discovery — agent-specific details in metadata.
struct DiscoveredSession: Identifiable, Sendable {
    let id: String
    let pid: Int32
    let cwd: String
    let startedAt: Date
    let backendName: String
    let iconName: String
    /// Agent-specific extras stored as JSON-encodable dictionary.
    let metadata: [String: String]
}
