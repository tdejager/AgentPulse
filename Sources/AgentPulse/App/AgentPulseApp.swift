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
        .defaultSize(width: 360, height: 400)

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
    @State private var showHelp = false
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
                    .help("Diagnostics")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .help("Help")
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
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Help")
                        .font(.headline)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Text("Session States")
                    .font(.subheadline.bold())

                VStack(alignment: .leading, spacing: 8) {
                    stateRow(color: Color.green, label: "Active", description: "Agent is working — running tools, generating text")
                    stateRow(color: Color.orange, label: "Waiting for input", description: "Turn complete or the agent asked you a question")
                    stateRow(color: Color.red, label: "Needs approval", description: "Agent wants to run a tool and needs your permission")
                    stateRow(color: Color.gray, label: "Idle", description: "No recent activity")
                }

                Divider()

                Text("Notifications")
                    .font(.subheadline.bold())

                Text("AgentPulse sends a notification when a session switches to **Waiting for input** or **Needs approval**.")
                    .font(.caption)

                Text("If notifications aren't appearing:")
                    .font(.caption.bold())

                VStack(alignment: .leading, spacing: 4) {
                    bulletPoint("Open **System Settings > Notifications > AgentPulse** and enable alerts")
                    bulletPoint("If using a **Focus mode**, add AgentPulse to the allowed apps")
                    bulletPoint("Enable **Time Sensitive** notifications for AgentPulse to break through Focus")
                }

                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.caption)

                Divider()

                hooksSection

                Divider()

                Text("Click a session to switch to its terminal tab (Ghostty only).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(minWidth: 380, maxWidth: 380, minHeight: 300, maxHeight: 500)
    }

    @State private var hooksInstalled = HookInstaller.isInstalled()

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hooks")
                .font(.subheadline.bold())

            HStack {
                if hooksInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Not installed", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if hooksInstalled {
                    Button("Uninstall") {
                        HookInstaller.uninstall()
                        hooksInstalled = false
                    }
                    .font(.caption)
                } else {
                    Button("Install") {
                        try? HookInstaller.install()
                        hooksInstalled = HookInstaller.isInstalled()
                    }
                    .font(.caption)
                }
            }

            Text("Hooks provide instant state detection via Claude Code events. Without hooks, state is detected by watching log files (slightly delayed).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stateRow(color: Color, label: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bulletPoint(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.caption)
            Text(text)
                .font(.caption)
        }
    }
}
