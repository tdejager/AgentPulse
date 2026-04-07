# AgentPulse Testing Playbook

This document describes how to test AgentPulse end-to-end. A Claude Code agent can follow these steps to verify the app works correctly and debug any issues.

## Prerequisites

- macOS 14+ with Xcode Command Line Tools (`xcode-select --install`)
- Ghostty terminal (for tab switching tests)
- pixi installed (`curl -fsSL https://pixi.sh/install.sh | bash`)

## Quick Automated Tests

```bash
cd AgentPulse

# Unit tests (28 tests — state analysis logic)
pixi run test

# Integration tests (12 tests — hook server, state transitions, notifications)
pixi run integration-test
```

Both must show `ALL TESTS PASSED`. If not, read the failure output for which test failed and why.

## Building and Launching

```bash
# Build the .app bundle (debug)
pixi run bundle

# Launch the app
open build/AgentPulse.app

# Or build + launch in one step
pixi run run

# Launch with fake sessions (no Claude Code needed)
pixi run run-mock
```

## Reading App State

While the app is running, you can read its full state:

```bash
PORT=$(cat ~/.agentpulse/port)
curl -s "http://localhost:${PORT}/state" | python3 -m json.tool
```

This returns JSON with:
- `sessions` — array of tracked sessions with `id`, `projectName`, `state`, `cwd`, `pid`
- `hookBackend` — `trackedCount`, `hookEventCount`, `fileScanCount`
- `healthChecks` — array of checks with `name`, `status` (pass/warn/fail), `detail`
- `hooksInstalled`, `hookServerPort`, `notificationStatus`, `buildCommit`

## Reading Logs

```bash
# Live log stream (structured, categorized)
tail -f /tmp/agentpulse.log

# Filter by category
grep '\[hook\]' /tmp/agentpulse.log      # hook events
grep '\[state\]' /tmp/agentpulse.log     # state transitions
grep '\[notification\]' /tmp/agentpulse.log  # notification delivery
grep '\[discovery\]' /tmp/agentpulse.log # session discovery
grep '\[error\]' /tmp/agentpulse.log     # errors
```

## Testing Hook Events Manually

```bash
PORT=$(cat ~/.agentpulse/port)

# Simulate SessionStart
curl -s -X POST "http://localhost:${PORT}/event" \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name":"SessionStart","session_id":"test-1","cwd":"/tmp/test"}'

# Simulate Stop (should trigger "Waiting for input" + notification)
curl -s -X POST "http://localhost:${PORT}/event" \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name":"Stop","session_id":"test-1","cwd":"/tmp/test"}'

# Simulate PermissionRequest (should trigger "Needs approval" + notification)
curl -s -X POST "http://localhost:${PORT}/event" \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name":"PermissionRequest","session_id":"test-1","cwd":"/tmp/test","tool_name":"Bash"}'

# Simulate UserPromptSubmit (should go back to "Active")
curl -s -X POST "http://localhost:${PORT}/event" \
  -H "Content-Type: application/json" \
  -d '{"hook_event_name":"UserPromptSubmit","session_id":"test-1","cwd":"/tmp/test"}'
```

After each event, verify the state changed:
```bash
curl -s "http://localhost:${PORT}/state" | python3 -c "
import json, sys
state = json.load(sys.stdin)
for s in state['sessions']:
    if s['id'] == 'test-1':
        print(f\"Session test-1: state={s['state']}\")
"
```

## Testing Hook Installation

```bash
# Check if hooks are installed
cat ~/.claude/hooks/agentpulse-hook.sh 2>/dev/null && echo "Hook script: EXISTS" || echo "Hook script: MISSING"
python3 -c "
import json
with open('$HOME/.claude/settings.json') as f:
    d = json.load(f)
hooks = d.get('hooks', {})
events = [e for e in hooks if any('agentpulse' in h.get('command','') for entry in hooks[e] for h in entry.get('hooks',[]))]
print(f'Registered for: {events}')
" 2>/dev/null || echo "No hooks registered"
```

Expected: hook script exists, registered for `SessionStart`, `Stop`, `PermissionRequest`, `UserPromptSubmit`, `Notification`.

## Testing Real Claude Code Hook Delivery

This test requires a **new** Claude Code session (started AFTER hooks were installed):

```bash
# 1. Ensure hooks are installed (check via app Settings or the command above)
# 2. Open a new terminal tab
# 3. Run: claude
# 4. Type a prompt and wait for Claude to finish
# 5. Check for hook events in the app log:
grep '\[hook\].*received' /tmp/agentpulse.log | tail -5
# Should show lines like: [hook] HookServer: received Stop sessionId=...
```

If no `[hook]` entries appear in the log, the hooks aren't being triggered. Common causes:
- The Claude Code session was started BEFORE hooks were installed (restart it)
- The hook script isn't executable (`chmod +x ~/.claude/hooks/agentpulse-hook.sh`)
- The port file is stale (restart AgentPulse)

## Testing Notifications

1. Ensure notifications are enabled: System Settings > Notifications > AgentPulse
2. If using Focus mode, add AgentPulse to allowed apps
3. Check via state endpoint: `curl -s "http://localhost:$(cat ~/.agentpulse/port)/state" | python3 -c "import json,sys; print(json.load(sys.stdin)['notificationStatus'])"`
4. Should print `granted`
5. Send a Stop event (see "Testing Hook Events Manually" above) — a notification banner should appear

If notifications don't appear:
- Check the log: `grep '\[notification\]' /tmp/agentpulse.log | tail -10`
- Look for `Debounced` (wait 10s and retry), `No notification center!` (bundle issue), or `FAILED` (system error)
- Verify `notificationsEnabled` is true: the state endpoint shows this in healthChecks

## Testing Tab Switching (Ghostty)

1. Have multiple Ghostty tabs open, with Claude Code running in one
2. Click the session row in AgentPulse
3. Ghostty should activate and switch to the correct tab

If tab switching doesn't work:
- Check the log: `grep 'AppleScript' /tmp/agentpulse.log | tail -5`
- Look for "Not authorized to send Apple events" — grant Automation permission in System Settings > Privacy & Security > Automation > AgentPulse > Ghostty
- Look for "No tab found matching cwd" — the working directory might not match (e.g., if Claude was started from a different directory)

## Health Check Reference

The state endpoint includes health checks. All should be `pass`:

| Check | What it verifies |
|-------|-----------------|
| Hook script | `~/.claude/hooks/agentpulse-hook.sh` exists |
| Hooks in settings | Entries exist in `~/.claude/settings.json` |
| Hook server | Listening on a port |
| Port file | `~/.agentpulse/port` matches actual server port |
| Notification permission | macOS permission granted |
| Notifications enabled | User setting is on |
| Ghostty | Ghostty.app is running |
| Active sessions | At least one live Claude Code session found |

## Debugging Workflow

When something isn't working:

1. **Read state**: `curl -s "http://localhost:$(cat ~/.agentpulse/port)/state" | python3 -m json.tool`
2. **Check health**: Look at `healthChecks` in the state — any `fail` or `warn`?
3. **Read recent logs**: `tail -20 /tmp/agentpulse.log`
4. **Filter logs by category**: `grep '\[hook\]' /tmp/agentpulse.log | tail -10`
5. **Send a test event**: `curl -s -X POST "http://localhost:$(cat ~/.agentpulse/port)/event" -H "Content-Type: application/json" -d '{"hook_event_name":"Stop","session_id":"debug-test","cwd":"/tmp"}'`
6. **Check if it arrived**: `grep "debug-test" /tmp/agentpulse.log`
7. **Run integration tests**: `pixi run integration-test`

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Sessions show "log" badge, not "hooks" | Session started before hooks installed | Restart Claude Code session (not `--continue`) |
| No notifications | Focus mode blocking | Add AgentPulse to Focus allowed apps |
| No notifications | Permission not granted | System Settings > Notifications > AgentPulse |
| No notifications | First launch, setting not initialized | Open Settings, toggle notifications off then on |
| Tab switching fails | Automation permission denied | System Settings > Privacy & Security > Automation |
| State always "Active" | JSONL timestamp parsing issue | Check log for `analyzeEntries` lines |
| Empty port file | App crashed or wasn't started | Restart AgentPulse |
| Hook events not arriving | Hooks not loaded | Start a NEW Claude Code session |
