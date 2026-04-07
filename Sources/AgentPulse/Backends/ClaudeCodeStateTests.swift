import Foundation

/// Self-contained test harness for ClaudeCodeBackend state analysis.
/// Run with: swift AgentPulse/Sources/AgentPulse/Backends/ClaudeCodeStateTests.swift
/// Or call ClaudeCodeStateTests.runAll() from the app in debug mode.

enum ClaudeCodeStateTests {
    static func runAll() {
        var passed = 0
        var failed = 0

        func check(_ name: String, entries: [JSONLEntry], expected: SessionState, timePassed: TimeInterval = 0) {
            let backend = ClaudeCodeBackend()
            // For time-based checks, we offset timestamps into the past
            let adjusted: [JSONLEntry]
            if timePassed > 0 {
                adjusted = entries.map { e in
                    JSONLEntry(
                        type: e.type, subtype: e.subtype, uuid: e.uuid,
                        timestamp: e.timestamp.map { _ in Date().addingTimeInterval(-timePassed) },
                        stopReason: e.stopReason, contentTypes: e.contentTypes, toolName: e.toolName
                    )
                }
            } else {
                adjusted = entries.map { e in
                    JSONLEntry(
                        type: e.type, subtype: e.subtype, uuid: e.uuid,
                        timestamp: Date(), // "just happened"
                        stopReason: e.stopReason, contentTypes: e.contentTypes, toolName: e.toolName
                    )
                }
            }

            let result = backend.analyzeEntries(adjusted)
            if result == expected {
                passed += 1
            } else {
                print("  FAIL: \(name)")
                print("    expected: \(expected.label)")
                print("    got:      \(result.label)")
                failed += 1
            }
        }

        // Helper to create entries quickly
        func entry(_ type: String, sub: String? = nil, stop: String? = nil, ctypes: [String] = [], tool: String? = nil) -> JSONLEntry {
            JSONLEntry(type: type, subtype: sub, uuid: "", timestamp: Date(), stopReason: stop, contentTypes: ctypes, toolName: tool)
        }

        print("Running ClaudeCodeBackend state analysis tests...\n")

        // === WAITING FOR INPUT ===

        check("turn_duration → waitingForInput",
            entries: [
                entry("assistant", stop: "end_turn", ctypes: ["text"]),
                entry("system", sub: "turn_duration"),
            ],
            expected: .waitingForInput
        )

        check("end_turn → waitingForInput",
            entries: [
                entry("user", ctypes: ["tool_result"]),
                entry("assistant", stop: "end_turn", ctypes: ["text"]),
            ],
            expected: .waitingForInput
        )

        check("AskUserQuestion after 10s → waitingForInput",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "AskUserQuestion"),
            ],
            expected: .waitingForInput,
            timePassed: 10
        )

        // === ACTIVE ===

        check("tool_result just came back → active",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Bash"),
                entry("user", ctypes: ["tool_result"]),
            ],
            expected: .active
        )

        check("user sent new message → active",
            entries: [
                entry("system", sub: "turn_duration"),
                entry("user"),
            ],
            expected: .active
        )

        check("user sent text message → active",
            entries: [
                entry("user", ctypes: ["text"]),
            ],
            expected: .active
        )

        check("user sent image → active",
            entries: [
                entry("user", ctypes: ["text", "image"]),
            ],
            expected: .active
        )

        check("assistant streaming text (no stop_reason) → active",
            entries: [
                entry("assistant", ctypes: ["text"]),
            ],
            expected: .active
        )

        check("assistant streaming thinking → active",
            entries: [
                entry("assistant", ctypes: ["thinking"]),
            ],
            expected: .active
        )

        check("Bash just dispatched (< 2s) → active",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Bash"),
            ],
            expected: .active,
            timePassed: 0.5
        )

        check("AskUserQuestion just dispatched (< 2s) → active",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "AskUserQuestion"),
            ],
            expected: .active,
            timePassed: 0.5
        )

        check("rapid tool calls (Bash result then next tool) → active",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Bash"),
                entry("user", ctypes: ["tool_result"]),
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Edit"),
                entry("user", ctypes: ["tool_result"]),
            ],
            expected: .active
        )

        check("TaskCreate (no stop_reason, streaming) → active",
            entries: [
                entry("assistant", ctypes: ["tool_use"], tool: "TaskCreate"),
            ],
            expected: .active
        )

        check("TaskUpdate (no stop_reason, streaming) → active",
            entries: [
                entry("assistant", ctypes: ["tool_use"], tool: "TaskUpdate"),
            ],
            expected: .active
        )

        // === PERMISSION REQUEST ===

        check("Bash waiting > 1s → permissionRequest",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Bash"),
            ],
            expected: .permissionRequest("Bash"),
            timePassed: 10
        )

        check("Write waiting > 1s → permissionRequest",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Write"),
            ],
            expected: .permissionRequest("Write"),
            timePassed: 10
        )

        check("Edit waiting > 1s → permissionRequest",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Edit"),
            ],
            expected: .permissionRequest("Edit"),
            timePassed: 10
        )

        // === IDLE ===

        check("empty entries → idle",
            entries: [],
            expected: .idle
        )

        check("old activity → idle",
            entries: [
                entry("assistant", ctypes: ["text"]),
            ],
            expected: .idle,
            timePassed: 120
        )

        // === NON-MEANINGFUL ENTRIES FILTERED ===

        check("turn_duration followed by file-history-snapshot → waitingForInput",
            entries: [
                entry("assistant", stop: "end_turn", ctypes: ["text"]),
                entry("system", sub: "turn_duration"),
                entry("file-history-snapshot"),
            ],
            expected: .waitingForInput
        )

        check("progress entries ignored → active",
            entries: [
                entry("user", ctypes: ["tool_result"]),
                entry("progress"),
                entry("progress"),
            ],
            expected: .active
        )

        check("queue-operation ignored → active",
            entries: [
                entry("user", ctypes: ["tool_result"]),
                entry("queue-operation"),
            ],
            expected: .active
        )

        check("api_error system message → still shows last meaningful state",
            entries: [
                entry("user", ctypes: ["tool_result"]),
                entry("system", sub: "api_error"),
            ],
            expected: .active
        )

        // === EDGE CASES ===

        check("ExitPlanMode tool → permissionRequest after 5s (not user-facing)",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "ExitPlanMode"),
            ],
            expected: .permissionRequest("ExitPlanMode"),
            timePassed: 10
        )

        check("Agent tool dispatched → active when recent",
            entries: [
                entry("assistant", stop: "tool_use", ctypes: ["tool_use"], tool: "Agent"),
            ],
            expected: .active,
            timePassed: 0.5
        )

        check("stop_sequence → waitingForInput (refusal/limit)",
            entries: [
                entry("assistant", stop: "stop_sequence", ctypes: ["text"]),
            ],
            expected: .waitingForInput
        )

        // Print results
        print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
        if failed > 0 {
            print("SOME TESTS FAILED")
        } else {
            print("ALL TESTS PASSED")
        }
    }
}
