import SwiftUI

struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            // State indicator dot
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)

            // Agent icon
            Image(systemName: session.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(session.state.label)
                        .font(.caption)
                        .foregroundStyle(stateLabelColor)

                    if case .permissionRequest(let tool) = session.state {
                        Text("(\(tool))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Time since last activity
            Text(timeAgo(session.lastActivity))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var stateColor: Color {
        switch session.state {
        case .active: .green
        case .waitingForInput: .orange
        case .permissionRequest: .red
        case .idle: .gray
        case .dead: .gray.opacity(0.5)
        }
    }

    private var stateLabelColor: Color {
        switch session.state {
        case .active: .secondary
        case .waitingForInput: .orange
        case .permissionRequest: .red
        case .idle: .secondary
        case .dead: .secondary
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
