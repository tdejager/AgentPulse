import SwiftUI

struct SessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)

            Image(systemName: session.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.projectName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    // Source indicator
                    Text(session.source == "hooks" ? "hooks" : "log")
                        .font(.system(.caption2, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(session.source == "hooks" ? Color.purple.opacity(0.15) : Color.gray.opacity(0.15))
                        )
                        .foregroundStyle(session.source == "hooks" ? .purple : .secondary)
                }

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
