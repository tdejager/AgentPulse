import AppKit

enum TerminalFocuser {
    static let ghosttyBundleId = "com.mitchellh.ghostty"

    /// Attempt to bring the terminal running this session to the foreground
    /// and switch to the correct tab using Ghostty's native AppleScript API.
    static func focusSession(_ session: AgentSession) {
        logDebug("focusSession called for PID \(session.pid) (\(session.projectName)) cwd=\(session.cwd)")

        let ghosttyApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: ghosttyBundleId
        )
        guard ghosttyApps.first != nil else {
            logDebug("Ghostty not running")
            return
        }

        // Use AppleScript to find the tab whose terminal working directory matches
        // the session's cwd, then select it. This is more reliable than TTY mapping
        // because tab order can differ from TTY creation order.
        let escapedCwd = session.cwd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Ghostty"
            activate
            set targetCwd to "\(escapedCwd)"
            set tabList to every tab of window 1
            repeat with t in tabList
                set termList to every terminal of t
                repeat with trm in termList
                    if working directory of trm is targetCwd then
                        select tab t
                        return index of t
                    end if
                end repeat
            end repeat
            return 0
        end tell
        """

        logDebug("Running AppleScript to find tab with cwd=\(session.cwd)")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            if let error {
                logDebug("AppleScript error: \(error)")
            } else {
                let tabIndex = result.int32Value
                if tabIndex > 0 {
                    logDebug("Switched to tab \(tabIndex)")
                } else {
                    logDebug("No tab found matching cwd")
                }
            }
        }
    }
}
