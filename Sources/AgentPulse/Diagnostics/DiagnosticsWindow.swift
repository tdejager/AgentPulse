import SwiftUI

struct DiagnosticsWindow: View {
    let store: SessionStore
    let hookServer: HookServer
    let hookBackend: ClaudeCodeHookBackend

    var body: some View {
        TabView {
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
            StateInspectorView(store: store, hookServer: hookServer, hookBackend: hookBackend)
                .tabItem { Label("State", systemImage: "heart.text.square") }
            EventSimulatorView(hookBackend: hookBackend, store: store)
                .tabItem { Label("Simulator", systemImage: "play.circle") }
        }
    }
}
