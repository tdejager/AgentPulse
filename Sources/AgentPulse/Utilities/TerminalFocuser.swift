import AppKit

enum TerminalFocuser {
    static let ghosttyBundleId = "com.mitchellh.ghostty"

    /// Attempt to bring the terminal running this session to the foreground
    /// and switch to the correct tab.
    static func focusSession(_ session: AgentSession) {
        logDebug("focusSession called for PID \(session.pid) (\(session.projectName))")

        // Find the Ghostty app
        let ghosttyApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: ghosttyBundleId
        )
        guard let ghostty = ghosttyApps.first else {
            logDebug("Ghostty not running")
            return
        }

        let ghosttyPid = ghostty.processIdentifier

        // Hide AgentPulse first so it doesn't steal focus back
        NSApp.hide(nil)

        // Find which tab this session is in by mapping PID → TTY → tab index
        if let tabIndex = findTabIndex(sessionPid: session.pid, terminalPid: ghosttyPid) {
            logDebug("Session is in tab \(tabIndex + 1)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ghostty.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    switchToTab(tabIndex + 1)
                }
            }
        } else {
            logDebug("Could not determine tab index, just activating Ghostty")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ghostty.activate()
            }
        }
    }

    /// Find the tab index for a session by mapping:
    /// session PID → TTY → sorted position among terminal's login children
    private static func findTabIndex(sessionPid: Int32, terminalPid: Int32) -> Int? {
        // Get the TTY of the session
        guard let sessionTty = getTty(pid: sessionPid) else {
            logDebug("Could not get TTY for session PID \(sessionPid)")
            return nil
        }
        logDebug("Session PID \(sessionPid) is on \(sessionTty)")

        // Get all direct children of the terminal (login processes, one per tab)
        let children = getChildPids(parentPid: terminalPid)
        logDebug("Ghostty has \(children.count) children")

        // Map each child to its TTY and sort
        var ttyList: [(tty: String, pid: Int32)] = []
        for childPid in children {
            if let tty = getTty(pid: childPid) {
                ttyList.append((tty, childPid))
            }
        }
        ttyList.sort { $0.tty < $1.tty }

        logDebug("TTY mapping: \(ttyList.map { "\($0.tty)→\($0.pid)" }.joined(separator: ", "))")

        // Find our TTY's position = tab index
        return ttyList.firstIndex { $0.tty == sessionTty }
    }

    /// Get the TTY name for a process (e.g. "ttys003")
    private static func getTty(pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return nil }

        // pbi_tdev is the device number of the controlling terminal
        let devNo = info.e_tdev
        if devNo == UInt32(bitPattern: -1) { return nil } // no controlling terminal

        // Convert device number to tty name by checking /dev/ttysXXX
        // The minor number gives us the tty index
        let minor = Int(devNo & 0xFFFF)
        return String(format: "ttys%03d", minor)
    }

    /// Get all direct child PIDs of a process.
    private static func getChildPids(parentPid: Int32) -> [Int32] {
        // Get total number of running processes
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(bufferSize))
        let count = proc_listallpids(&pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard count > 0 else { return [] }

        var children: [Int32] = []
        for i in 0..<Int(count) {
            let pid = pids[i]
            if pid <= 0 { continue }
            var info = proc_bsdinfo()
            let size = MemoryLayout<proc_bsdinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
            if result == size && Int32(info.pbi_ppid) == parentPid {
                children.append(pid)
            }
        }
        return children
    }

    /// Send Cmd+N keystroke to switch to tab N in Ghostty.
    /// Uses AppleScript via System Events for reliability.
    private static func switchToTab(_ tabNumber: Int) {
        guard tabNumber >= 1 && tabNumber <= 9 else { return }
        logDebug("Sending Cmd+\(tabNumber) to Ghostty")

        let script = """
        tell application "System Events"
            tell process "ghostty"
                keystroke "\(tabNumber)" using command down
            end tell
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logDebug("AppleScript error: \(error)")
            }
        }
    }
}
