import SwiftUI

@main
struct AgentPulseApp: App {
    @State private var store: SessionStore
    @AppStorage("useMockBackend") private var useMockBackend = false

    init() {
        // Run tests and exit if --test flag
        if CommandLine.arguments.contains("--test") {
            ClaudeCodeStateTests.runAll()
            exit(0)
        }

        let useMock = CommandLine.arguments.contains("--mock")
            || UserDefaults.standard.bool(forKey: "useMockBackend")

        let backends: [AgentBackend]
        if useMock {
            backends = [MockReplayBackend()]
        } else {
            backends = [ClaudeCodeBackend()]
        }

        _store = State(initialValue: SessionStore(backends: backends))
    }

    var body: some Scene {
        Window("AgentPulse", id: "main") {
            ContentView(store: store)
                .onAppear {
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
                }
                .onDisappear {
                    store.stopMonitoring()
                }
        }
        .defaultSize(width: 360, height: 400)

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

    var body: some View {
        SessionListView(store: store)
            .toolbar {
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

            Text("Click a session to switch to its terminal tab (Ghostty only).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 340)
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
