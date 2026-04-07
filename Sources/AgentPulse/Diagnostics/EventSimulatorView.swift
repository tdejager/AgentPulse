import SwiftUI

struct EventSimulatorView: View {
    let hookBackend: ClaudeCodeHookBackend
    let store: SessionStore

    @State private var selectedEvent = "SessionStart"
    @State private var sessionId = "sim-\(UUID().uuidString.prefix(8))"
    @State private var cwd = "/tmp/simulated-project"
    @State private var toolName = "Bash"
    @State private var lifecycleRunning = false

    private let eventTypes = ["SessionStart", "Stop", "PermissionRequest", "UserPromptSubmit", "Notification"]

    var body: some View {
        Form {
            Section("Event") {
                Picker("Type", selection: $selectedEvent) {
                    ForEach(eventTypes, id: \.self) { Text($0) }
                }

                HStack {
                    TextField("Session ID", text: $sessionId)
                        .font(.system(.body, design: .monospaced))
                    Button("Random") {
                        sessionId = "sim-\(UUID().uuidString.prefix(8))"
                    }
                    .font(.caption)
                }

                TextField("Working Directory", text: $cwd)
                    .font(.system(.body, design: .monospaced))

                if selectedEvent == "PermissionRequest" {
                    TextField("Tool Name", text: $toolName)
                }
            }

            Section("Actions") {
                Button("Send Event") {
                    sendEvent(selectedEvent)
                }
                .buttonStyle(.borderedProminent)

                Button("Send Lifecycle (SessionStart → UserPrompt → Stop)") {
                    sendLifecycle()
                }
                .disabled(lifecycleRunning)

                if lifecycleRunning {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Lifecycle running...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sendEvent(_ eventName: String) {
        let event = HookEvent(
            eventName: eventName,
            sessionId: sessionId,
            cwd: cwd,
            toolName: eventName == "PermissionRequest" ? toolName : nil,
            notificationType: eventName == "Notification" ? "elicitation_dialog" : nil
        )
        hookBackend.handleEvent(event)
        Task { @MainActor in
            await store.refresh()
        }
        logDebug("Simulated event: \(eventName)", category: .hook, metadata: [
            "sessionId": sessionId,
            "simulated": "true",
        ])
    }

    private func sendLifecycle() {
        lifecycleRunning = true
        Task {
            sendEvent("SessionStart")
            try? await Task.sleep(for: .seconds(2))
            sendEvent("UserPromptSubmit")
            try? await Task.sleep(for: .seconds(3))
            sendEvent("Stop")
            await MainActor.run { lifecycleRunning = false }
        }
    }
}
