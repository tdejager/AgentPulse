import Foundation

/// Manages installation/uninstallation of Claude Code hooks for AgentPulse.
/// Pure Swift — uses FileManager and JSONSerialization to manage files.
enum HookInstaller {
    private static let hookScriptPath = NSHomeDirectory() + "/.claude/hooks/agentpulse-hook.sh"
    private static let settingsPath = NSHomeDirectory() + "/.claude/settings.json"

    private static let hookEvents = [
        "SessionStart", "Stop", "PermissionRequest", "UserPromptSubmit", "Notification"
    ]

    /// Check if hooks are installed (script exists + settings entries present).
    static func isInstalled() -> Bool {
        guard FileManager.default.fileExists(atPath: hookScriptPath) else { return false }
        guard let settings = readSettings() else { return false }
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }

        // Check that at least the key events are registered
        for event in ["Stop", "PermissionRequest"] {
            guard hooks[event] != nil else { return false }
        }
        return true
    }

    /// Install the hook script and register it in settings.local.json.
    static func install() throws {
        // 1. Create hook script
        let hooksDir = NSHomeDirectory() + "/.claude/hooks"
        try FileManager.default.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        let portDir = NSHomeDirectory() + "/.agentpulse"
        let script = """
        #!/bin/bash
        PORT=$(cat \(portDir)/port 2>/dev/null) || exit 0
        INPUT=$(cat)
        curl -s -X POST "http://localhost:${PORT}/event" \
          -H "Content-Type: application/json" \
          -d "$INPUT" 2>/dev/null || true
        """

        try script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)

        // Make executable
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o755]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: hookScriptPath)

        // 2. Register hooks in settings.local.json
        var settings = readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookEntry: [String: Any] = [
            "matcher": "",
            "hooks": [[
                "type": "command",
                "command": "bash \(hookScriptPath)",
                "timeout": 5
            ]]
        ]

        for event in hookEvents {
            var eventHooks = hooks[event] as? [[String: Any]] ?? []
            // Remove any existing agentpulse entries
            eventHooks.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { ($0["command"] as? String)?.contains("agentpulse") == true }
                }
                return false
            }
            eventHooks.append(hookEntry)
            hooks[event] = eventHooks
        }

        settings["hooks"] = hooks

        // 3. Write settings atomically
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)

        logDebug("HookInstaller: installed hooks", category: .hook)
    }

    /// Uninstall the hook script and remove entries from settings.local.json.
    static func uninstall() {
        // Remove hook script
        try? FileManager.default.removeItem(atPath: hookScriptPath)

        // Remove entries from settings
        guard var settings = readSettings(),
              var hooks = settings["hooks"] as? [String: Any]
        else { return }

        for event in hookEvents {
            guard var eventHooks = hooks[event] as? [[String: Any]] else { continue }
            eventHooks.removeAll { entry in
                if let entryHooks = entry["hooks"] as? [[String: Any]] {
                    return entryHooks.contains { ($0["command"] as? String)?.contains("agentpulse") == true }
                }
                return false
            }
            if eventHooks.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventHooks
            }
        }

        settings["hooks"] = hooks
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        }

        logDebug("HookInstaller: uninstalled hooks", category: .hook)
    }

    private static func readSettings() -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }
}
