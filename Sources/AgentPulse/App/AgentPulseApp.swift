import SwiftUI

@main
struct AgentPulseApp: App {
    @State private var store: SessionStore
    @AppStorage("useMockBackend") private var useMockBackend = false

    init() {
        // Run tests and exit if --test flag
        if CommandLine.arguments.contains("--test") {
            ClaudeCodeStateTests.runAll()
            exit(0)
        }

        let useMock = CommandLine.arguments.contains("--mock")
            || UserDefaults.standard.bool(forKey: "useMockBackend")

        let backends: [AgentBackend]
        if useMock {
            backends = [MockReplayBackend()]
        } else {
            backends = [ClaudeCodeBackend()]
        }

        _store = State(initialValue: SessionStore(backends: backends))
    }

    var body: some Scene {
        Window("AgentPulse", id: "main") {
            ContentView(store: store)
                .onAppear {
                    NotificationManager.shared.requestPermission()
                    store.onAttentionNeeded = { session in
                        NotificationManager.shared.notifyIfNeeded(session: session)
                    }
                    NotificationManager.shared.onNotificationClicked = { sessionId in
                        if let session = store.sessions.first(where: { $0.id == sessionId }) {
                            TerminalFocuser.focusSession(session)
                        }
                    }
                    store.startMonitoring()
                }
                .onDisappear {
                    store.stopMonitoring()
                }
        }
        .defaultSize(width: 360, height: 400)

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

struct ContentView: View {
    let store: SessionStore

    var body: some View {
        SessionListView(store: store)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh sessions")
                }
            }
            .navigationTitle("AgentPulse")
    }
}
