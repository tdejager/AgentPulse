import SwiftUI

struct SessionListView: View {
    let store: SessionStore

    var body: some View {
        Group {
            if store.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }

    private var sessionList: some View {
        List(store.sessions) { session in
            Button {
                TerminalFocuser.focusSession(session)
            } label: {
                SessionRow(session: session)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No active agent sessions")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Start a Claude Code session in your terminal\nand it will appear here automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
