import Foundation
import Darwin

enum ProcessProbe {
    /// Check if a process is alive using kill(pid, 0).
    static func isAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    /// Get the executable path of a process.
    static func getProcessPath(_ pid: Int32) -> String? {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let result = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        guard result > 0 else { return nil }
        return String(cString: pathBuffer)
    }
}
