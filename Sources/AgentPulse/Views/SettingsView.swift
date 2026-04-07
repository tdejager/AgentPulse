import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("useMockBackend") private var useMockBackend = false
    @State private var hooksInstalled = HookInstaller.isInstalled()

    var body: some View {
        Form {
            Section("Detection") {
                HStack {
                    Text("Backend")
                    Spacer()
                    if useMockBackend {
                        Text("Mock")
                            .foregroundStyle(.secondary)
                    } else if hooksInstalled {
                        Label("Hooks (instant)", systemImage: "bolt.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Log file watching (delayed)", systemImage: "doc.text.magnifyingglass")
                            .foregroundStyle(.orange)
                    }
                }

                if !hooksInstalled && !useMockBackend {
                    Button("Install Hooks") {
                        try? HookInstaller.install()
                        hooksInstalled = HookInstaller.isInstalled()
                    }
                    Text("Hooks provide instant state detection. Requires app restart after installing.")
                        .foregroundStyle(.secondary)
                } else if hooksInstalled && !useMockBackend {
                    Button("Uninstall Hooks") {
                        HookInstaller.uninstall()
                        hooksInstalled = false
                    }
                }
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Debug") {
                Toggle("Use mock backend (requires restart)", isOn: $useMockBackend)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
        .padding()
        .onAppear {
            hooksInstalled = HookInstaller.isInstalled()
        }
    }
}
