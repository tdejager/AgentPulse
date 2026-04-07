import AppKit

enum TerminalFocuser {
    static let ghosttyBundleId = "com.mitchellh.ghostty"

    /// Attempt to bring the terminal running this session to the foreground
    /// and switch to the correct tab using Ghostty's native AppleScript API.
    static func focusSession(_ session: AgentSession) {
        logDebug("focusSession called for PID \(session.pid) (\(session.projectName))")

        let ghosttyApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: ghosttyBundleId
        )
        guard let ghostty = ghosttyApps.first else {
            logDebug("Ghostty not running")
            return
        }

        // Hide AgentPulse so it doesn't steal focus back
        NSApp.hide(nil)

        let ghosttyPid = ghostty.processIdentifier

        if let tabIndex = findTabIndex(sessionPid: session.pid, terminalPid: ghosttyPid) {
            let tabNumber = tabIndex + 1 // AppleScript tabs are 1-indexed
            logDebug("Selecting tab \(tabNumber) via AppleScript")
            selectGhosttyTab(tabNumber)
        } else {
            logDebug("Could not determine tab index, just activating Ghostty")
            ghostty.activate()
        }
    }

    /// Use Ghostty's native AppleScript `select tab` command.
    private static func selectGhosttyTab(_ tabNumber: Int) {
        let script = """
        tell application "Ghostty"
            activate
            select tab \(tabNumber) of window 1
        end tell
        """

        logDebug("Running AppleScript: select tab \(tabNumber) of window 1")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logDebug("AppleScript error: \(error)")
            }
        }
    }

    /// Find the tab index for a session by mapping:
    /// session PID → TTY → sorted position among terminal's login children
    private static func findTabIndex(sessionPid: Int32, terminalPid: Int32) -> Int? {
        guard let sessionTty = getTty(pid: sessionPid) else {
            logDebug("Could not get TTY for session PID \(sessionPid)")
            return nil
        }
        logDebug("Session PID \(sessionPid) is on \(sessionTty)")

        let children = getChildPids(parentPid: terminalPid)
        logDebug("Ghostty has \(children.count) children")

        var ttyList: [(tty: String, pid: Int32)] = []
        for childPid in children {
            if let tty = getTty(pid: childPid) {
                ttyList.append((tty, childPid))
            }
        }
        ttyList.sort { $0.tty < $1.tty }

        logDebug("TTY mapping: \(ttyList.map { "\($0.tty)→\($0.pid)" }.joined(separator: ", "))")

        return ttyList.firstIndex { $0.tty == sessionTty }
    }

    /// Get the TTY name for a process (e.g. "ttys003")
    private static func getTty(pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        guard result == size else { return nil }

        let devNo = info.e_tdev
        if devNo == UInt32(bitPattern: -1) { return nil }

        let minor = Int(devNo & 0xFFFF)
        return String(format: "ttys%03d", minor)
    }

    /// Get all direct child PIDs of a process.
    private static func getChildPids(parentPid: Int32) -> [Int32] {
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
}
