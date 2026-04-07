import Foundation
import Darwin

enum ProcessProbe {
    /// Check if a process is alive using kill(pid, 0).
    static func isAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
