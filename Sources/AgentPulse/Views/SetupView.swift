import SwiftUI

struct SetupView: View {
    @Binding var isPresented: Bool
    @State private var installed = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Welcome to AgentPulse")
                .font(.headline)

            Text("AgentPulse monitors your Claude Code sessions and notifies you when they need input. For instant state detection, it installs lightweight hooks into Claude Code.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if installed {
                Label("Hooks installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Restart any running Claude Code sessions to activate hooks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)

                Button("Retry") { installHooks() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Set Up") { installHooks() }
                    .buttonStyle(.borderedProminent)
            }

            if !installed {
                Button("Skip") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(30)
        .frame(width: 320)
    }

    private func installHooks() {
        do {
            try HookInstaller.install()
            NotificationManager.shared.requestPermission()
            installed = true
            error = nil
        } catch {
            self.error = "Failed to install hooks: \(error.localizedDescription)"
        }
    }
}
