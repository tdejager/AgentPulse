import Foundation

/// Monitors a single discovered session by reacting to JSONL file changes (push-based).
/// When a tool_use is the last entry, schedules a deferred re-check to detect
/// if the agent is waiting for user input.
final class SessionMonitor: @unchecked Sendable {
    let session: DiscoveredSession
    private let backend: AgentBackend
    private var tailReader: JSONLTailReader?
    private var livenessTimer: DispatchSourceTimer?
    private let onStateChange: @Sendable (SessionState) -> Void

    /// Pending deferred re-check for tool_use entries.
    private var deferredCheck: DispatchWorkItem?
    private let checkQueue = DispatchQueue(label: "session-monitor")

    init(
        session: DiscoveredSession,
        backend: AgentBackend,
        onStateChange: @escaping @Sendable (SessionState) -> Void
    ) {
        self.session = session
        self.backend = backend
        self.onStateChange = onStateChange
    }

    deinit {
        stop()
    }

    func start() {
        // Start file tailing if there's a watch path
        if let watchPath = backend.watchPath(for: session) {
            tailReader = JSONLTailReader(path: watchPath) { [weak self] _ in
                self?.onFileChanged()
            }
            tailReader?.start()
        }

        // Liveness check every 10s
        let timer = DispatchSource.makeTimerSource(queue: checkQueue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if !self.backend.isAlive(session: self.session) {
                self.onStateChange(.dead)
            }
        }
        timer.resume()
        livenessTimer = timer

        // Initial state check
        checkState()
    }

    func stop() {
        tailReader?.stop()
        tailReader = nil
        livenessTimer?.cancel()
        livenessTimer = nil
        deferredCheck?.cancel()
        deferredCheck = nil
    }

    /// Called immediately when the JSONL file changes (push from kqueue).
    private func onFileChanged() {
        // Cancel any pending deferred check — we have fresh data
        deferredCheck?.cancel()
        deferredCheck = nil

        checkState()
    }

    private func checkState() {
        Task {
            let state = try await backend.analyzeState(for: session)
            onStateChange(state)

            // If the state is active but the backend might need a deferred re-check
            // (e.g. tool_use just dispatched, need to wait and see if it's a permission prompt)
            if state == .active {
                scheduleDeferredCheck()
            }
        }
    }

    /// Schedule a one-shot re-check after the attention threshold.
    /// If the tool_use is still the last entry by then, it means the agent
    /// is waiting for user input/permission.
    private func scheduleDeferredCheck() {
        deferredCheck?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.checkState()
        }
        deferredCheck = work

        // Re-check after the backend's attention threshold + small buffer
        let delay = (backend as? ClaudeCodeBackend)?.attentionThresholdSeconds ?? 2.0
        checkQueue.asyncAfter(deadline: .now() + delay + 0.5, execute: work)
    }
}
