import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationSound") private var notificationSound = true
    @AppStorage("permissionThreshold") private var permissionThreshold = 3.0
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("useMockBackend") private var useMockBackend = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Toggle("Notification sound", isOn: $notificationSound)
                    .disabled(!notificationsEnabled)

                VStack(alignment: .leading) {
                    Text("Permission detection threshold: \(String(format: "%.0f", permissionThreshold))s")
                    Slider(value: $permissionThreshold, in: 1...10, step: 1)
                }
            }

            Section("Window") {
                Toggle("Always on top", isOn: $alwaysOnTop)
            }

            Section("Debug") {
                Toggle("Use mock backend", isOn: $useMockBackend)
                    .help("Use fake sessions for testing without running real agents")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .padding()
    }
}
