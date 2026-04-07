import SwiftUI

struct SessionListView: View {
    let store: SessionStore
    @State private var notificationStatus: NotificationStatus = .unknown
    @State private var hooksInstalled = false

    var body: some View {
        VStack(spacing: 0) {
            if !hooksInstalled {
                hooksBanner
            }
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

            // Build info footer
            HStack {
                Text("Build: \(buildCommit)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 380, minHeight: 250)
        .onAppear {
            refreshStatus()
            NotificationManager.shared.onStatusChange = { status in
                DispatchQueue.main.async {
                    self.notificationStatus = status
                }
            }
            NotificationManager.shared.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
    }

    private func refreshStatus() {
        hooksInstalled = HookInstaller.isInstalled()
        NotificationManager.shared.refreshStatus()
    }

    private var hooksBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.circle")
                .foregroundStyle(.white)
                .font(.caption)
            Text("Install hooks for instant detection")
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
            Button("Install") {
                try? HookInstaller.install()
                hooksInstalled = HookInstaller.isInstalled()
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.9))
            .underline()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.blue)
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
