import Foundation

enum LogCategory: String, CaseIterable, Sendable {
    case discovery
    case state
    case hook
    case notification
    case error
}

struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let category: LogCategory
    let message: String
    let metadata: [String: String]
}

@Observable
@MainActor
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}

// MARK: - Global logging function (callable from any thread)

private let logFilePath = "/tmp/agentpulse.log"
private let logFileQueue = DispatchQueue(label: "agentpulse-log-file")

func logDebug(
    _ message: String,
    category: LogCategory = .state,
    metadata: [String: String] = [:]
) {
    let entry = LogEntry(
        id: UUID(),
        timestamp: Date(),
        category: category,
        message: message,
        metadata: metadata
    )

    // Write to file synchronously on a dedicated queue (fast, non-blocking for caller)
    logFileQueue.async {
        let metaStr = metadata.isEmpty ? "" : " " + metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        let line = "[\(ISO8601DateFormatter().string(from: entry.timestamp))] [\(category.rawValue)] \(message)\(metaStr)\n"
        if let handle = FileHandle(forWritingAtPath: logFilePath) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: logFilePath, contents: line.data(using: .utf8))
        }
    }

    // Dispatch to main actor for in-memory UI storage
    Task { @MainActor in
        DiagnosticsLog.shared.append(entry)
    }
}
