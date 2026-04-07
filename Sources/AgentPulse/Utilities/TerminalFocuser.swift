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
            select tab (tab \(tabNumber) of window 1)
        end tell
        """

        logDebug("Running AppleScript: select tab (tab \(tabNumber) of window 1)")
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logDebug("AppleScript error: \(error)")
            }
        }
    }

    /// Find the tab index for a session by mapping:
    /// session PID → TTY → sorted position among Ghostty's tabs
    private static func findTabIndex(sessionPid: Int32, terminalPid: Int32) -> Int? {
        guard let sessionTty = getTty(pid: sessionPid) else {
            logDebug("Could not get TTY for session PID \(sessionPid)")
            return nil
        }
        logDebug("Session PID \(sessionPid) is on \(sessionTty)")

        // Ghostty spawns root-owned login processes (one per tab).
        // We can't read full info for root processes, so we use PROC_PIDT_SHORTBSDINFO
        // to find them, then get the TTY from their first user-owned child.
        let loginPids = getChildPidsShort(parentPid: terminalPid)
        logDebug("Ghostty has \(loginPids.count) children (login processes)")

        var ttyList: [(tty: String, loginPid: Int32)] = []
        let allPids = listAllPids()
        for loginPid in loginPids {
            if let tty = getTtyViaChild(loginPid: loginPid, allPids: allPids) {
                ttyList.append((tty, loginPid))
            }
        }
        ttyList.sort { $0.tty < $1.tty }

        logDebug("TTY mapping: \(ttyList.map { "\($0.tty)→\($0.loginPid)" }.joined(separator: ", "))")

        return ttyList.firstIndex { $0.tty == sessionTty }
    }

    /// Get the TTY of a user-owned process.
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

    /// Get TTY for a root-owned login process by reading its first user-owned child.
    private static func getTtyViaChild(loginPid: Int32, allPids: [Int32]) -> String? {
        for pid in allPids {
            if pid <= 0 { continue }
            var shortInfo = proc_bsdshortinfo()
            let shortSize = MemoryLayout<proc_bsdshortinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &shortInfo, Int32(shortSize))
            if result == shortSize && Int32(shortInfo.pbsi_ppid) == loginPid && shortInfo.pbsi_uid != 0 {
                // Found a user-owned child — get its TTY via full info
                return getTty(pid: pid)
            }
        }
        return nil
    }

    /// List all PIDs on the system (cached for a single focusSession call).
    private static func listAllPids() -> [Int32] {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bufferSize))
        let count = proc_listallpids(&pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    /// Get direct child PIDs using PROC_PIDT_SHORTBSDINFO (works for root-owned processes).
    private static func getChildPidsShort(parentPid: Int32) -> [Int32] {
        let allPids = listAllPids()
        var children: [Int32] = []
        for pid in allPids {
            if pid <= 0 { continue }
            var info = proc_bsdshortinfo()
            let size = MemoryLayout<proc_bsdshortinfo>.size
            let result = proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, Int32(size))
            if result == size && Int32(info.pbsi_ppid) == parentPid {
                children.append(pid)
            }
        }
        return children
    }
}
