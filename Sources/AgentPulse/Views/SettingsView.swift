import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("useMockBackend") private var useMockBackend = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Debug") {
                Toggle("Use mock backend (requires restart)", isOn: $useMockBackend)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .padding()
    }
}
