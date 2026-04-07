import Foundation

enum SessionState: Equatable, Sendable {
    case active
    case waitingForInput
    case permissionRequest(String)
    case idle
    case dead

    var label: String {
        switch self {
        case .active: "Active"
        case .waitingForInput: "Waiting for input"
        case .permissionRequest: "Needs approval"
        case .idle: "Idle"
        case .dead: "Dead"
        }
    }

    var isAttentionNeeded: Bool {
        switch self {
        case .waitingForInput, .permissionRequest: true
        default: false
        }
    }
}

struct AgentSession: Identifiable, Sendable {
    let id: String
    let backendName: String
    let iconName: String
    let pid: Int32
    let cwd: String
    var state: SessionState
    var lastActivity: Date
    var projectName: String
    var lastMessage: String?

    init(from discovered: DiscoveredSession, state: SessionState = .active) {
        self.id = discovered.id
        self.backendName = discovered.backendName
        self.iconName = discovered.iconName
        self.pid = discovered.pid
        self.cwd = discovered.cwd
        self.state = state
        self.lastActivity = Date()
        self.projectName = (discovered.cwd as NSString).lastPathComponent
        self.lastMessage = nil
    }
}
