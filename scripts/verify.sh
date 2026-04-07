#!/bin/bash
# AgentPulse Verification Script
# Run this to verify AgentPulse is working correctly.
# Can be run by any Claude Code agent or human.
# Usage: bash scripts/verify.sh
set -euo pipefail

PASS=0
FAIL=0
WARN=0

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN + 1)); }

echo "═══════════════════════════════════════════"
echo " AgentPulse Verification"
echo "═══════════════════════════════════════════"
echo ""

# --- Phase 1: Build ---
echo "📦 Phase 1: Build"

if swift build 2>&1 | grep -q "Build complete"; then
    pass "Swift build succeeds"
else
    fail "Swift build failed"
    echo "    Run 'swift build' for details"
    exit 1
fi

# --- Phase 2: Unit Tests ---
echo ""
echo "🧪 Phase 2: Unit Tests"

UNIT_OUT=$(swift run AgentPulse --test 2>&1)
if echo "$UNIT_OUT" | grep -q "ALL TESTS PASSED"; then
    COUNT=$(echo "$UNIT_OUT" | grep -o '[0-9]* tests' | head -1)
    pass "Unit tests pass ($COUNT)"
else
    fail "Unit tests failed"
    echo "$UNIT_OUT" | grep "FAIL" | head -5
fi

# --- Phase 3: Integration Tests ---
echo ""
echo "🔗 Phase 3: Integration Tests"

INT_OUT=$(swift run AgentPulse --integration-test 2>&1)
if echo "$INT_OUT" | grep -q "ALL TESTS PASSED"; then
    COUNT=$(echo "$INT_OUT" | grep -o '[0-9]* tests' | head -1)
    pass "Integration tests pass ($COUNT)"
else
    fail "Integration tests failed"
    echo "$INT_OUT" | grep -E "FAIL|PASS" | head -15
fi

# --- Phase 4: App Bundle ---
echo ""
echo "📱 Phase 4: App Bundle"

BUNDLE_OUT=$(bash build-app.sh debug 2>&1)
if echo "$BUNDLE_OUT" | grep -q "Build complete"; then
    pass "App bundle builds"
else
    fail "App bundle build failed"
    echo "$BUNDLE_OUT" | tail -5
fi

if [ -f build/AgentPulse.app/Contents/MacOS/AgentPulse ]; then
    pass "Executable exists in bundle"
else
    fail "Executable missing from bundle"
fi

if [ -f build/AgentPulse.app/Contents/Info.plist ]; then
    pass "Info.plist in bundle"
else
    fail "Info.plist missing"
fi

if [ -f build/AgentPulse.app/Contents/Resources/AppIcon.icns ]; then
    pass "App icon in bundle"
else
    warn "App icon missing (run: bash scripts/generate-icon.sh)"
fi

# --- Phase 5: Hook Infrastructure ---
echo ""
echo "🪝 Phase 5: Hook Infrastructure"

if [ -f ~/.claude/hooks/agentpulse-hook.sh ]; then
    pass "Hook script installed"
    if [ -x ~/.claude/hooks/agentpulse-hook.sh ]; then
        pass "Hook script is executable"
    else
        fail "Hook script not executable"
    fi
else
    warn "Hook script not installed (install from app Settings or setup wizard)"
fi

if python3 -c "
import json, os, sys
path = os.path.expanduser('~/.claude/settings.local.json')
if not os.path.exists(path): sys.exit(1)
with open(path) as f: d = json.load(f)
hooks = d.get('hooks', {})
needed = ['Stop', 'PermissionRequest', 'SessionStart']
found = [e for e in needed if any('agentpulse' in h.get('command','') for entry in hooks.get(e,[]) for h in entry.get('hooks',[]))]
sys.exit(0 if len(found) == len(needed) else 1)
" 2>/dev/null; then
    pass "Hooks registered in settings.local.json"
else
    warn "Hooks not registered (install from app)"
fi

# --- Phase 6: Live App Test ---
echo ""
echo "🚀 Phase 6: Live App Test"

# Kill any existing instance
pkill -f "AgentPulse" 2>/dev/null || true
sleep 1

# Launch the app
build/AgentPulse.app/Contents/MacOS/AgentPulse &
APP_PID=$!
sleep 3

if kill -0 $APP_PID 2>/dev/null; then
    pass "App launches and stays running"
else
    fail "App crashed on launch"
    echo "    Check console for errors"
fi

# Check port file
PORT_FILE=~/.agentpulse/port
if [ -f "$PORT_FILE" ] && [ -s "$PORT_FILE" ]; then
    PORT=$(cat "$PORT_FILE")
    pass "Port file written (port $PORT)"
else
    fail "Port file missing or empty"
    kill $APP_PID 2>/dev/null || true
    exit 1
fi

# Read state
STATE=$(curl -s "http://localhost:${PORT}/state" 2>/dev/null)
if echo "$STATE" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "GET /state returns valid JSON"
else
    fail "GET /state failed or invalid JSON"
fi

# Check build commit in state
COMMIT=$(echo "$STATE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('buildCommit',''))" 2>/dev/null)
if [ -n "$COMMIT" ] && [ "$COMMIT" != "dev" ]; then
    pass "Build commit in state: $COMMIT"
else
    warn "Build commit is '$COMMIT' (expected a git hash)"
fi

# Check health
HEALTH_FAILS=$(echo "$STATE" | python3 -c "
import json, sys
state = json.load(sys.stdin)
fails = [c for c in state.get('healthChecks', []) if c['status'] == 'fail']
for f in fails: print(f'    {f[\"name\"]}: {f[\"detail\"]}')
print(len(fails))
" 2>/dev/null)
FAIL_COUNT=$(echo "$HEALTH_FAILS" | tail -1)
if [ "$FAIL_COUNT" = "0" ]; then
    pass "All health checks pass"
else
    warn "Some health checks failing:"
    echo "$HEALTH_FAILS" | head -n -1
fi

# Send a test hook event
curl -s -X POST "http://localhost:${PORT}/event" \
    -H "Content-Type: application/json" \
    -d '{"hook_event_name":"SessionStart","session_id":"verify-test","cwd":"/tmp/verify"}' > /dev/null
sleep 1

# Check it arrived
VERIFY_SESSION=$(curl -s "http://localhost:${PORT}/state" | python3 -c "
import json, sys
state = json.load(sys.stdin)
sessions = [s for s in state.get('sessions', []) if s['id'] == 'verify-test']
if sessions:
    print(sessions[0]['state'])
else:
    print('NOT_FOUND')
" 2>/dev/null)

if [ "$VERIFY_SESSION" = "Active" ]; then
    pass "Hook event → session created (state=Active)"
else
    fail "Hook event didn't create session (got: $VERIFY_SESSION)"
fi

# Send Stop and verify state change
curl -s -X POST "http://localhost:${PORT}/event" \
    -H "Content-Type: application/json" \
    -d '{"hook_event_name":"Stop","session_id":"verify-test","cwd":"/tmp/verify"}' > /dev/null
sleep 1

VERIFY_STATE=$(curl -s "http://localhost:${PORT}/state" | python3 -c "
import json, sys
state = json.load(sys.stdin)
sessions = [s for s in state.get('sessions', []) if s['id'] == 'verify-test']
print(sessions[0]['state'] if sessions else 'NOT_FOUND')
" 2>/dev/null)

if [ "$VERIFY_STATE" = "Waiting for input" ]; then
    pass "Stop event → Waiting for input"
else
    fail "Stop event didn't transition (got: $VERIFY_STATE)"
fi

# Check notification was attempted
if grep -q "Firing notification.*verify" /tmp/agentpulse.log 2>/dev/null; then
    pass "Notification fired for test session"
else
    warn "Notification not found in log (may be debounced)"
fi

# Clean up
kill $APP_PID 2>/dev/null || true

# --- Summary ---
echo ""
echo "═══════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "═══════════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
    echo ""
    echo "Some tests failed. Check the output above for details."
    exit 1
else
    echo ""
    echo "All checks passed! AgentPulse is working correctly."
    exit 0
fi
