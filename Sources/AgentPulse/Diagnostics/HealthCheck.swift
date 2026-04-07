import Foundation
import AppKit
import UserNotifications

struct HealthCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let detail: String
    let action: (() -> Void)?

    enum Status { case pass, warn, fail }
}

@MainActor
func runHealthChecks(hookServer: HookServer, hookBackend: ClaudeCodeHookBackend) -> [HealthCheck] {
    var checks: [HealthCheck] = []

    // 1. Hook script exists
    let hookPath = NSHomeDirectory() + "/.claude/hooks/agentpulse-hook.sh"
    let hookExists = FileManager.default.fileExists(atPath: hookPath)
    checks.append(HealthCheck(
        name: "Hook script",
        status: hookExists ? .pass : .fail,
        detail: hookExists ? "Installed" : "Missing",
        action: hookExists ? nil : { try? HookInstaller.install() }
    ))

    // 2. Hooks registered in settings
    let hooksRegistered = HookInstaller.isInstalled()
    checks.append(HealthCheck(
        name: "Hooks in settings",
        status: hooksRegistered ? .pass : .fail,
        detail: hooksRegistered ? "Registered" : "Not registered",
        action: hooksRegistered ? nil : { try? HookInstaller.install() }
    ))

    // 3. Hook server listening
    let port = hookServer.port
    checks.append(HealthCheck(
        name: "Hook server",
        status: port > 0 ? .pass : .fail,
        detail: port > 0 ? "Port \(port)" : "Not started",
        action: nil
    ))

    // 4. Port file matches
    let portFilePath = NSHomeDirectory() + "/.agentpulse/port"
    let filePort = (try? String(contentsOfFile: portFilePath, encoding: .utf8)).flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    let portMatches = filePort == port && port > 0
    checks.append(HealthCheck(
        name: "Port file",
        status: portMatches ? .pass : (port > 0 ? .warn : .fail),
        detail: portMatches ? "Matches (\(port))" : filePort.map { "Stale (file=\($0), actual=\(port))" } ?? "Missing",
        action: nil
    ))

    // 5. Notification permission (async — use cached status)
    let notifStatus = NotificationManager.shared.status
    checks.append(HealthCheck(
        name: "Notification permission",
        status: notifStatus == .granted ? .pass : (notifStatus == .denied ? .fail : .warn),
        detail: {
            switch notifStatus {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .noBundleId: return "No bundle ID"
            case .unknown: return "Unknown"
            }
        }(),
        action: notifStatus == .denied ? {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        } : nil
    ))

    // 6. Notifications enabled (user setting)
    let notifEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
    checks.append(HealthCheck(
        name: "Notifications enabled",
        status: notifEnabled ? .pass : .warn,
        detail: notifEnabled ? "Enabled" : "Disabled in settings",
        action: nil
    ))

    // 7. Ghostty running
    let ghosttyRunning = !NSRunningApplication.runningApplications(
        withBundleIdentifier: "com.mitchellh.ghostty"
    ).isEmpty
    checks.append(HealthCheck(
        name: "Ghostty",
        status: ghosttyRunning ? .pass : .warn,
        detail: ghosttyRunning ? "Running" : "Not running",
        action: nil
    ))

    // 8. Active sessions
    let sessionsDir = NSHomeDirectory() + "/.claude/sessions"
    let sessionFiles = (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir))?.filter { $0.hasSuffix(".json") } ?? []
    let liveSessions = sessionFiles.filter { file in
        let path = (sessionsDir as NSString).appendingPathComponent(file)
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int
        else { return false }
        return ProcessProbe.isAlive(pid: Int32(pid))
    }
    checks.append(HealthCheck(
        name: "Active sessions",
        status: liveSessions.isEmpty ? .warn : .pass,
        detail: liveSessions.isEmpty ? "None found" : "\(liveSessions.count) session(s)",
        action: nil
    ))

    return checks
}
