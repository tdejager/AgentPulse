import SwiftUI

@main
struct AgentPulseApp: App {
    @State private var store: SessionStore
    @AppStorage("useMockBackend") private var useMockBackend = false
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var showSetup = false

    private let hookServer = HookServer()
    private let hookBackend: ClaudeCodeHookBackend

    init() {
        #if DEBUG
        // Run unit tests and exit
        if CommandLine.arguments.contains("--test") {
            ClaudeCodeStateTests.runAll()
            exit(0)
        }
        // Run integration tests and exit
        if CommandLine.arguments.contains("--integration-test") {
            Task { @MainActor in
                await IntegrationTests.runAll()
                exit(0)
            }
            // Need to start the run loop for async to work
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 30))
            exit(1) // timeout
        }
        #endif

        let useMock = CommandLine.arguments.contains("--mock")
            || UserDefaults.standard.bool(forKey: "useMockBackend")

        let hb = ClaudeCodeHookBackend()
        self.hookBackend = hb

        let backends: [AgentBackend]
        if useMock {
            backends = [MockReplayBackend()]
        } else if HookInstaller.isInstalled() {
            backends = [hb]
        } else {
            backends = [ClaudeCodeBackend()]
        }

        _store = State(initialValue: SessionStore(backends: backends))
    }

    var body: some Scene {
        Window("AgentPulse (\(buildCommit))", id: "main") {
            ContentView(store: store)
                .onAppear {
                    // Start hook server
                    hookServer.onEvent = { [hookBackend] event in
                        hookBackend.handleEvent(event)
                        // Trigger a refresh so the UI picks up the new state
                        Task { @MainActor in
                            await store.refresh()
                        }
                    }
                    hookServer.onStateRequest = { [store, hookBackend] in
                        let sessions = store.sessions.map { session -> [String: Any] in
                            [
                                "id": session.id,
                                "projectName": session.projectName,
                                "state": session.state.label,
                                "cwd": session.cwd,
                                "pid": session.pid,
                                "backendName": session.backendName,
                            ]
                        }
                        let info = hookBackend.diagnosticInfo
                        let checks = runHealthChecks(hookServer: hookServer, hookBackend: hookBackend)
                        return [
                            "buildCommit": buildCommit,
                            "buildDate": buildDate,
                            "hookServerPort": hookServer.port,
                            "hooksInstalled": HookInstaller.isInstalled(),
                            "notificationStatus": NotificationManager.shared.status == .granted ? "granted" : "not granted",
                            "sessions": sessions,
                            "hookBackend": [
                                "trackedCount": info.trackedCount,
                                "hookEventCount": info.hookEventCount,
                                "fileScanCount": info.fileScanCount,
                            ],
                            "healthChecks": checks.map { [
                                "name": $0.name,
                                "status": $0.status == .pass ? "pass" : $0.status == .warn ? "warn" : "fail",
                                "detail": $0.detail,
                            ] },
                        ]
                    }
                    hookServer.start()

                    NotificationManager.shared.requestPermission()
                    store.onAttentionNeeded = { session in
                        NotificationManager.shared.notifyIfNeeded(session: session)
                    }
                    NotificationManager.shared.onNotificationClicked = { sessionId in
                        if let session = store.sessions.first(where: { $0.id == sessionId }) {
                            TerminalFocuser.focusSession(session)
                        }
                    }
                    store.startMonitoring()

                    // Show setup on first launch
                    if !setupComplete {
                        showSetup = true
                    }
                }
                .onDisappear {
                    store.stopMonitoring()
                    hookServer.stop()
                }
                .sheet(isPresented: $showSetup) {
                    SetupView(isPresented: $showSetup)
                        .onDisappear { setupComplete = true }
                }
        }
        .defaultSize(width: 420, height: 500)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsWindow(store: store, hookServer: hookServer, hookBackend: hookBackend)
        }
        .defaultSize(width: 650, height: 500)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

struct ContentView: View {
    let store: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SessionListView(store: store)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        openWindow(id: "diagnostics")
                    } label: {
                        Image(systemName: "ladybug")
                    }
                    .help("Diagnostics & Help")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh sessions")
                }
            }
            .navigationTitle("AgentPulse")
    }
}

// HelpView moved to DiagnosticsWindow as HelpTab
