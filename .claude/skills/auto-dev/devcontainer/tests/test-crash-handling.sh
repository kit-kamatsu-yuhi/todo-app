#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/test-helper.sh"

TEST_STATE_DIR=$(mktemp -d)
TEST_LOG_DIR=$(mktemp -d)
export STATE_DIR="$TEST_STATE_DIR"
export LOG_DIR="$TEST_LOG_DIR"
export AUTO_DEV_LOCK_TTL=60
export AUTO_DEV_REPO="test/repo"

LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
source "${LIB_DIR}/state.sh"

cleanup() { rm -rf "$TEST_STATE_DIR" "$TEST_LOG_DIR"; }
trap cleanup EXIT

echo "=== crash handling tests ==="

# --- Lock released on worker crash ---

echo ""
echo "Lock released on crash:"

# Create a mock worker that acquires lock then crashes
MOCK_WORKER=$(mktemp)
cat > "$MOCK_WORKER" <<WORKER
#!/bin/bash
set -uo pipefail
ISSUE_NUM="\$1"
export STATE_DIR="$TEST_STATE_DIR"
export LOG_DIR="$TEST_LOG_DIR"
export AUTO_DEV_REPO="test/repo"
export LIB_DIR="$LIB_DIR"
source "${LIB_DIR}/state.sh"

# Simplified crash handler (same logic as worker.sh)
on_worker_exit() {
    local exit_code=\$?
    if [ "\$exit_code" -ne 0 ]; then
        set_issue_state "\$ISSUE_NUM" "failure" 2>/dev/null || true
    fi
    unlock_issue "\$ISSUE_NUM" 2>/dev/null || true
}
trap on_worker_exit EXIT

lock_issue "\$ISSUE_NUM"
exit 1  # Simulate crash
WORKER
chmod +x "$MOCK_WORKER"

# Run the crashing worker
"$MOCK_WORKER" "700" 2>/dev/null || true

assert_false "lock released after worker crash" is_issue_locked "700"

STATE=$(get_issue_state "700")
assert_eq "failure" "$STATE" "state set to failure on crash"

rm -f "$MOCK_WORKER"

# --- Lock released on normal exit ---

echo ""
echo "Lock released on normal exit:"

NORMAL_WORKER=$(mktemp)
cat > "$NORMAL_WORKER" <<WORKER
#!/bin/bash
set -uo pipefail
ISSUE_NUM="\$1"
export STATE_DIR="$TEST_STATE_DIR"
export LIB_DIR="$LIB_DIR"
source "${LIB_DIR}/state.sh"

on_worker_exit() {
    unlock_issue "\$ISSUE_NUM" 2>/dev/null || true
}
trap on_worker_exit EXIT

lock_issue "\$ISSUE_NUM"
exit 0
WORKER
chmod +x "$NORMAL_WORKER"

"$NORMAL_WORKER" "701" 2>/dev/null || true
assert_false "lock released after normal exit" is_issue_locked "701"

rm -f "$NORMAL_WORKER"

# --- Summary ---
print_summary
