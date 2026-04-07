import Foundation
import Darwin

enum ProcessProbe {
    /// Check if a process is alive using kill(pid, 0).
    /// Returns false for pid <= 0 since kill(0, 0) signals the entire process group.
    static func isAlive(pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }
}
