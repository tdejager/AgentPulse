#if DEBUG
import Foundation

/// Integration test harness that exercises the full hook → state → notification pipeline.
/// Run with: swift run AgentPulse --integration-test
@MainActor
enum IntegrationTests {
    static func runAll() async {
        var passed = 0
        var failed = 0

        func check(_ name: String, _ condition: Bool, detail: String = "") {
            if condition {
                passed += 1
                print("  PASS: \(name)")
            } else {
                failed += 1
                print("  FAIL: \(name) \(detail)")
            }
        }

        print("Running AgentPulse integration tests...\n")

        // Set up the app components
        let hookBackend = ClaudeCodeHookBackend()
        let store = SessionStore(backends: [hookBackend])
        let hookServer = HookServer()

        hookServer.onEvent = { event in
            hookBackend.handleEvent(event)
            Task { @MainActor in await store.refresh() }
        }
        hookServer.start()

        store.onAttentionNeeded = { session in
            logDebug("Integration test: attention needed for \(session.projectName)", category: .notification)
        }

        // Create a fake session file so the test session survives pruning
        let myPid = ProcessInfo.processInfo.processIdentifier
        let sessionsDir = NSHomeDirectory() + "/.claude/sessions"
        let fakeSessionFile = "\(sessionsDir)/\(myPid).json"
        let fakeSessionJson = """
        {"pid":\(myPid),"sessionId":"inttest-1","cwd":"/tmp/integration-test","startedAt":\(Int(Date().timeIntervalSince1970 * 1000)),"kind":"interactive","entrypoint":"cli"}
        """
        try? fakeSessionJson.write(toFile: fakeSessionFile, atomically: true, encoding: .utf8)

        // Wait for server to start
        try? await Task.sleep(for: .seconds(1))

        // === Test 1: Hook server starts and writes port file ===
        let port = hookServer.port
        check("Hook server starts", port > 0, detail: "port=\(port)")

        let portFilePath = NSHomeDirectory() + "/.agentpulse/port"
        let filePort = (try? String(contentsOfFile: portFilePath, encoding: .utf8))
            .flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        check("Port file written", filePort == port, detail: "file=\(filePort ?? 0) actual=\(port)")

        // === Test 2: HTTP POST to hook server works ===
        let testUrl = URL(string: "http://localhost:\(port)/event")!
        let testJson = """
        {"hook_event_name":"SessionStart","session_id":"inttest-1","cwd":"/tmp/integration-test"}
        """.data(using: .utf8)!

        var request = URLRequest(url: testUrl)
        request.httpMethod = "POST"
        request.httpBody = testJson
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (_, response) = try! await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        check("HTTP POST returns 200", httpResponse.statusCode == 200)

        try? await Task.sleep(for: .seconds(1))

        // === Test 3: SessionStart creates a session ===
        await store.refresh()
        let session1 = store.sessions.first { $0.id == "inttest-1" }
        check("SessionStart creates session", session1 != nil)
        check("Session state is active", session1?.state == .active)
        check("Session cwd matches", session1?.cwd == "/tmp/integration-test")

        // === Test 4: Stop transitions to waitingForInput ===
        await postEvent(port: port, json: """
        {"hook_event_name":"Stop","session_id":"inttest-1","cwd":"/tmp/integration-test"}
        """)
        let state4 = await waitForState(store: store, sessionId: "inttest-1", expected: .waitingForInput)
        check("Stop → waitingForInput", state4 == .waitingForInput, detail: "got: \(state4?.label ?? "nil")")

        // === Test 5: PermissionRequest transitions to permissionRequest ===
        await postEvent(port: port, json: """
        {"hook_event_name":"PermissionRequest","session_id":"inttest-1","cwd":"/tmp/integration-test","tool_name":"Bash"}
        """)
        let state5 = await waitForState(store: store, sessionId: "inttest-1", expected: .permissionRequest("Bash"))
        check("PermissionRequest → permissionRequest", state5 == .permissionRequest("Bash"), detail: "got: \(state5?.label ?? "nil")")

        // === Test 6: UserPromptSubmit transitions to active ===
        await postEvent(port: port, json: """
        {"hook_event_name":"UserPromptSubmit","session_id":"inttest-1","cwd":"/tmp/integration-test"}
        """)
        let state6 = await waitForState(store: store, sessionId: "inttest-1", expected: .active)
        check("UserPromptSubmit → active", state6 == .active, detail: "got: \(state6?.label ?? "nil")")

        // === Test 7: Notification fires on attention transition ===
        DiagnosticsLog.shared.clear()
        await postEvent(port: port, json: """
        {"hook_event_name":"UserPromptSubmit","session_id":"inttest-1","cwd":"/tmp/integration-test"}
        """)
        try? await Task.sleep(for: .seconds(0.5))
        await store.refresh()
        // Now transition to Stop — should fire notification
        await postEvent(port: port, json: """
        {"hook_event_name":"Stop","session_id":"inttest-1","cwd":"/tmp/integration-test"}
        """)
        try? await Task.sleep(for: .seconds(2))
        await store.refresh()
        let hasNotifLog = DiagnosticsLog.shared.entries.contains {
            $0.category == .notification && $0.message.contains("Firing notification")
        }
        check("Notification fired on Stop", hasNotifLog)

        // === Test 8: Health checks run without crashing ===
        let checks = runHealthChecks(hookServer: hookServer, hookBackend: hookBackend)
        check("Health checks run", !checks.isEmpty, detail: "\(checks.count) checks")
        let serverCheck = checks.first { $0.name == "Hook server" }
        check("Hook server health: pass", serverCheck?.status == .pass)

        // Clean up
        hookServer.stop()
        store.stopMonitoring()
        try? FileManager.default.removeItem(atPath: fakeSessionFile)

        // Results
        print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
        if failed > 0 {
            print("SOME TESTS FAILED")
        } else {
            print("ALL TESTS PASSED")
        }
    }

    /// Poll store.refresh() until the session reaches expected state, or timeout.
    private static func waitForState(
        store: SessionStore,
        sessionId: String,
        expected: SessionState,
        timeout: TimeInterval = 3.0
    ) async -> SessionState? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            await store.refresh()
            if let session = store.sessions.first(where: { $0.id == sessionId }),
               session.state == expected {
                return session.state
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Return whatever state we have after timeout
        await store.refresh()
        return store.sessions.first { $0.id == sessionId }?.state
    }

    private static func postEvent(port: UInt16, json: String) async {
        let url = URL(string: "http://localhost:\(port)/event")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = json.data(using: .utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }
}
#endif
