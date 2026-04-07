import Foundation
import UserNotifications

final class NotificationManager: NSObject, @unchecked Sendable {
    static let shared = NotificationManager()

    /// Stored reference — set once during requestPermission().
    private var center: UNUserNotificationCenter?

    /// Track last notification per session to debounce.
    private var lastNotified: [String: (state: SessionState, time: Date)] = [:]
    private let debounceInterval: TimeInterval = 10.0

    var onNotificationClicked: ((String) -> Void)?

    override init() {
        super.init()
    }

    func requestPermission() {
        logDebug("Bundle identifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        guard Bundle.main.bundleIdentifier != nil else {
            logDebug("NotificationManager: no bundle identifier, notifications disabled")
            return
        }

        let nc = UNUserNotificationCenter.current()
        nc.delegate = self
        self.center = nc

        setupCategories()
        nc.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            logDebug("Notification permission granted: \(granted)")
            if let error {
                logDebug("Notification permission error: \(error)")
            }
            nc.getNotificationSettings { settings in
                logDebug("Notification settings: authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue) alertStyle=\(settings.alertStyle.rawValue)")
            }
        }
    }

    func notifyIfNeeded(session: AgentSession) {
        logDebug("notifyIfNeeded: \(session.projectName), state: \(session.state.label)")
        guard let center else {
            logDebug("No notification center!")
            return
        }
        // Re-assert delegate in case it was lost
        center.delegate = self

        // Debounce: don't re-notify for the same state within the interval
        if let last = lastNotified[session.id],
           last.state == session.state,
           Date().timeIntervalSince(last.time) < debounceInterval {
            logDebug("Debounced notification for \(session.projectName)")
            return
        }

        lastNotified[session.id] = (session.state, Date())

        let content = UNMutableNotificationContent()
        content.userInfo = ["sessionId": session.id]
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Tink.aiff"))
        content.interruptionLevel = .timeSensitive

        switch session.state {
        case .waitingForInput:
            content.title = "\(session.backendName) needs input"
            content.subtitle = session.projectName
            content.body = session.lastMessage ?? "Session is waiting for your input"
            content.categoryIdentifier = "AGENT_INPUT"

        case .permissionRequest(let tool):
            content.title = "\(session.backendName) needs approval"
            content.subtitle = session.projectName
            content.body = "Waiting for permission to use: \(tool)"
            content.categoryIdentifier = "AGENT_APPROVAL"

        default:
            return
        }

        let requestId = "session-\(session.id)-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(
            identifier: requestId,
            content: content,
            trigger: nil
        )

        logDebug("Delivering notification '\(requestId)': \(content.title)")
        center.add(request) { error in
            if let error {
                logDebug("Notification delivery FAILED: \(error)")
            } else {
                logDebug("Notification delivered OK: \(requestId)")
            }
        }
    }

    func clearNotifications(for sessionId: String) {
        lastNotified.removeValue(forKey: sessionId)
    }

    private func setupCategories() {
        guard let center else { return }
        let inputCategory = UNNotificationCategory(
            identifier: "AGENT_INPUT",
            actions: [],
            intentIdentifiers: []
        )
        let approvalCategory = UNNotificationCategory(
            identifier: "AGENT_APPROVAL",
            actions: [],
            intentIdentifiers: []
        )
        center.setNotificationCategories([inputCategory, approvalCategory])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        if let sessionId {
            onNotificationClicked?(sessionId)
        }
        completionHandler()
    }

    // Show notifications even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logDebug("willPresent notification: \(notification.request.content.title)")
        completionHandler([.banner, .sound, .list])
    }
}
