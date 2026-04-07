import SwiftUI

struct StateInspectorView: View {
    let store: SessionStore
    let hookServer: HookServer
    let hookBackend: ClaudeCodeHookBackend
    @State private var healthChecks: [HealthCheck] = []

    var body: some View {
        Form {
            Section("Health") {
                ForEach(healthChecks) { check in
                    HStack {
                        Image(systemName: statusIcon(check.status))
                            .foregroundStyle(statusColor(check.status))
                            .frame(width: 16)
                        Text(check.name)
                            .font(.caption)
                        Spacer()
                        Text(check.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let action = check.action {
                            Button("Fix") { action() ; refresh() }
                                .font(.caption2)
                                .controlSize(.small)
                        }
                    }
                }

                Button("Re-check") { refresh() }
                    .font(.caption)
            }

            Section("Sessions (\(store.sessions.count))") {
                if store.sessions.isEmpty {
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessions) { session in
                        HStack {
                            Circle()
                                .fill(stateColor(session.state))
                                .frame(width: 8, height: 8)
                            Text(session.projectName)
                                .font(.caption)
                            Spacer()
                            Text(session.state.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Hook Backend") {
                let info = hookBackend.diagnosticInfo
                LabeledContent("Tracked sessions") { Text("\(info.trackedCount)").font(.caption) }
                LabeledContent("Via hooks") { Text("\(info.hookEventCount)").font(.caption) }
                LabeledContent("Via file scan") { Text("\(info.fileScanCount)").font(.caption) }
            }
            .font(.caption)
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private func refresh() {
        healthChecks = runHealthChecks(hookServer: hookServer, hookBackend: hookBackend)
    }

    private func statusIcon(_ status: HealthCheck.Status) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }

    private func statusColor(_ status: HealthCheck.Status) -> Color {
        switch status {
        case .pass: .green
        case .warn: .orange
        case .fail: .red
        }
    }

    private func stateColor(_ state: SessionState) -> Color {
        switch state {
        case .active: .green
        case .waitingForInput: .orange
        case .permissionRequest: .red
        case .idle: .gray
        case .dead: .gray.opacity(0.5)
        }
    }
}
