import Foundation
import Network

/// Lightweight HTTP server on localhost that receives Claude Code hook events.
/// The hook script POSTs JSON to http://localhost:<port>/event
final class HookServer: @unchecked Sendable {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    var onEvent: ((HookEvent) -> Void)?

    private let portFilePath: String = {
        let dir = NSHomeDirectory() + "/.agentpulse"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/port"
    }()

    func start() {
        do {
            // Use port 0 to let the OS pick an available port
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: .any)
        } catch {
            logDebug("HookServer: failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let port = self?.listener?.port?.rawValue {
                    self?.port = port
                    self?.writePortFile(port)
                    logDebug("HookServer: listening on port \(port)")
                }
            case .failed(let error):
                logDebug("HookServer: failed: \(error)")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: DispatchQueue.global(qos: .utility))
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: portFilePath)
    }

    private func writePortFile(_ port: UInt16) {
        try? "\(port)".write(toFile: portFilePath, atomically: true, encoding: .utf8)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global(qos: .utility))

        // Read the full HTTP request
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let data, error == nil else {
                connection.cancel()
                return
            }
            guard let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Simple HTTP parsing — extract body after \r\n\r\n
            if let bodyRange = request.range(of: "\r\n\r\n") {
                let body = String(request[bodyRange.upperBound...])
                self?.parseAndDispatch(body)
            }

            // Send 200 OK response, then close
            let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func parseAndDispatch(_ body: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let event = HookEvent(
            eventName: json["hook_event_name"] as? String ?? "",
            sessionId: json["session_id"] as? String ?? "",
            cwd: json["cwd"] as? String ?? "",
            toolName: json["tool_name"] as? String,
            notificationType: json["notification_type"] as? String
        )

        logDebug("HookServer: received \(event.eventName) session=\(event.sessionId) tool=\(event.toolName ?? "")")
        onEvent?(event)
    }
}

struct HookEvent: Sendable {
    let eventName: String       // "SessionStart", "Stop", "PermissionRequest", etc.
    let sessionId: String
    let cwd: String
    let toolName: String?       // For PermissionRequest
    let notificationType: String? // For Notification events
}
