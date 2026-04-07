import Foundation

/// Tails a file using kqueue (via DispatchSource) and calls back with new lines.
/// Pure push-based — only fires when the file is actually modified.
final class JSONLTailReader: @unchecked Sendable {
    private let path: String
    private var fileHandle: FileHandle?
    private var lastOffset: UInt64 = 0
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let onChange: @Sendable ([String]) -> Void

    init(path: String, onChange: @escaping @Sendable ([String]) -> Void) {
        self.path = path
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard FileManager.default.fileExists(atPath: path) else { return }
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        fileHandle = handle

        // Seek near the end to avoid reading the entire file
        let fileSize = handle.seekToEndOfFile()
        let seekBack: UInt64 = min(fileSize, 4096)
        lastOffset = fileSize - seekBack
        handle.seek(toFileOffset: lastOffset)

        // Consume initial data so we don't report old entries
        _ = handle.readDataToEndOfFile()
        lastOffset = handle.offsetInFile

        // Set up kqueue monitoring via DispatchSource
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.readNewLines()
        }

        source.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        source.resume()
        dispatchSource = source
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    private func readNewLines() {
        guard let handle = fileHandle else { return }

        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        let newOffset = handle.offsetInFile

        guard newOffset > lastOffset, !data.isEmpty else { return }
        lastOffset = newOffset

        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        if !lines.isEmpty {
            onChange(lines)
        }
    }
}
