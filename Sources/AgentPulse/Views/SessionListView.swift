import SwiftUI

struct SessionListView: View {
    let store: SessionStore
    @State private var notificationStatus: NotificationStatus = .unknown

    var body: some View {
        VStack(spacing: 0) {
            if notificationStatus == .denied {
                notificationBanner
            }

            Group {
                if store.sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
        }
        .frame(minWidth: 320, minHeight: 200)
        .onAppear {
            NotificationManager.shared.onStatusChange = { status in
                DispatchQueue.main.async {
                    self.notificationStatus = status
                }
            }
            NotificationManager.shared.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            NotificationManager.shared.refreshStatus()
        }
    }

    private var notificationBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.white)
                .font(.caption)
            Text("Notifications are disabled.")
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .underline()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange)
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
