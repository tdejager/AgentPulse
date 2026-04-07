import SwiftUI

struct DiagnosticsWindow: View {
    let store: SessionStore
    let hookServer: HookServer
    let hookBackend: ClaudeCodeHookBackend

    var body: some View {
        TabView {
            HelpTab()
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            StateInspectorView(store: store, hookServer: hookServer, hookBackend: hookBackend)
                .tabItem { Label("State", systemImage: "heart.text.square") }
            EventSimulatorView(hookBackend: hookBackend, store: store)
                .tabItem { Label("Simulator", systemImage: "play.circle") }
        }
    }
}

struct HelpTab: View {
    @State private var hooksInstalled = HookInstaller.isInstalled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Session States")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 10) {
                    stateRow(color: Color.green, label: "Active", description: "Agent is working — running tools, generating text")
                    stateRow(color: Color.orange, label: "Waiting for input", description: "Turn complete or the agent asked you a question")
                    stateRow(color: Color.red, label: "Needs approval", description: "Agent wants to run a tool and needs your permission")
                    stateRow(color: Color.gray, label: "Idle", description: "No recent activity")
                }

                Divider()

                Text("Notifications")
                    .font(.headline)

                Text("AgentPulse sends a notification when a session switches to **Waiting for input** or **Needs approval**.")
                    .font(.body)

                Text("If notifications aren't appearing:")
                    .font(.body.bold())

                VStack(alignment: .leading, spacing: 6) {
                    bulletPoint("Open **System Settings > Notifications > AgentPulse** and enable alerts")
                    bulletPoint("If using a **Focus mode**, add AgentPulse to the allowed apps")
                    bulletPoint("Enable **Time Sensitive** notifications to break through Focus")
                }

                Button("Open Notification Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Text("Hooks")
                    .font(.headline)

                HStack {
                    if hooksInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not installed", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if hooksInstalled {
                        Button("Uninstall") {
                            HookInstaller.uninstall()
                            hooksInstalled = false
                        }
                    } else {
                        Button("Install") {
                            try? HookInstaller.install()
                            hooksInstalled = HookInstaller.isInstalled()
                        }
                    }
                }

                Text("Hooks provide instant state detection via Claude Code events. Without hooks, state is detected by watching log files (slightly delayed). Existing sessions need to be restarted after installing hooks.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Divider()

                Text("Click a session to switch to its terminal tab (Ghostty only).")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func stateRow(color: Color, label: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.bold())
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bulletPoint(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
            Text(text)
        }
    }
}
