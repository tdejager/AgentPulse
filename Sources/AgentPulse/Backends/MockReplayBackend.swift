import Foundation

/// A mock backend that cycles through session states on a timer.
/// Useful for developing and testing the UI and notification pipeline
/// without running a real Claude Code session.
final class MockReplayBackend: AgentBackend, @unchecked Sendable {
    let name = "Mock Agent"
    let iconName = "play.circle"

    private let stateSequence: [SessionState] = [
        .active,
        .active,
        .active,
        .waitingForInput,
        .waitingForInput,
        .active,
        .active,
        .permissionRequest("Bash"),
        .permissionRequest("Bash"),
        .active,
        .active,
        .active,
        .waitingForInput,
        .idle,
    ]

    private var currentIndex = 0
    private var lastAdvance = Date()
    private let advanceInterval: TimeInterval

    /// - Parameter advanceInterval: Seconds between state transitions (default 3s)
    init(advanceInterval: TimeInterval = 3.0) {
        self.advanceInterval = advanceInterval
    }

    func discoverSessions() async throws -> [DiscoveredSession] {
        [
            DiscoveredSession(
                id: "mock-session-001",
                pid: ProcessInfo.processInfo.processIdentifier,
                cwd: "/Users/mock/projects/my-app",
                startedAt: Date().addingTimeInterval(-300),
                backendName: name,
                iconName: iconName,
                metadata: [:]
            ),
            DiscoveredSession(
                id: "mock-session-002",
                pid: ProcessInfo.processInfo.processIdentifier,
                cwd: "/Users/mock/projects/another-project",
                startedAt: Date().addingTimeInterval(-120),
                backendName: name,
                iconName: iconName,
                metadata: [:]
            ),
        ]
    }

    func analyzeState(for session: DiscoveredSession) async throws -> SessionState {
        // Advance state based on time elapsed
        let now = Date()
        if now.timeIntervalSince(lastAdvance) >= advanceInterval {
            currentIndex = (currentIndex + 1) % stateSequence.count
            lastAdvance = now
        }

        // Second session is offset by half the sequence
        if session.id == "mock-session-002" {
            let offset = (currentIndex + stateSequence.count / 2) % stateSequence.count
            return stateSequence[offset]
        }

        return stateSequence[currentIndex]
    }

    func watchPath(for session: DiscoveredSession) -> String? {
        // No real file to watch in mock mode
        nil
    }

    func isAlive(session: DiscoveredSession) -> Bool {
        // Mock sessions are always alive
        true
    }
}
