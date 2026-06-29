#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/test-helper.sh"

TEST_STATE_DIR=$(mktemp -d)
TEST_LOG_DIR=$(mktemp -d)
export STATE_DIR="$TEST_STATE_DIR"
export LOG_DIR="$TEST_LOG_DIR"
export AUTO_DEV_LOCK_TTL=60

LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
source "${LIB_DIR}/state.sh"

cleanup() { rm -rf "$TEST_STATE_DIR" "$TEST_LOG_DIR"; }
trap cleanup EXIT

echo "=== dispatcher tests ==="

# Source dispatcher functions
source "${LIB_DIR}/dispatcher.sh"

# --- MAX_CONCURRENT enforcement ---

echo ""
echo "MAX_CONCURRENT enforcement:"

# Mock process-issue.sh with a sleep command
MOCK_WORKER=$(mktemp)
cat > "$MOCK_WORKER" <<'WORKER'
#!/bin/bash
ISSUE_NUM="$1"
STATE_DIR="$2"
mkdir -p "${STATE_DIR}/issue-${ISSUE_NUM}.lock.d" 2>/dev/null || true
echo "$$" > "${STATE_DIR}/issue-${ISSUE_NUM}.lock.d/pid"
date +%s > "${STATE_DIR}/issue-${ISSUE_NUM}.lock.d/timestamp"
sleep 3
rm -rf "${STATE_DIR}/issue-${ISSUE_NUM}.lock.d"
WORKER
chmod +x "$MOCK_WORKER"

# Test: MAX_CONCURRENT=2, dispatch 4 issues
export AUTO_DEV_MAX_CONCURRENT=2
PIDS=()

dispatch_workers "$MOCK_WORKER" "501 502 503 504" PIDS

# Count running workers immediately
RUNNING=0
for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        RUNNING=$((RUNNING + 1))
    fi
done

assert_eq "2" "$RUNNING" "only MAX_CONCURRENT workers running simultaneously"

# Wait for all to complete
wait "${PIDS[@]}" 2>/dev/null || true

# All locks should be released
assert_false "lock released for 501" [ -d "${STATE_DIR}/issue-501.lock.d" ]
assert_false "lock released for 502" [ -d "${STATE_DIR}/issue-502.lock.d" ]

rm -f "$MOCK_WORKER"

# --- Worker crash isolation ---

echo ""
echo "Worker crash isolation:"

CRASH_WORKER=$(mktemp)
cat > "$CRASH_WORKER" <<'WORKER'
#!/bin/bash
ISSUE_NUM="$1"
STATE_DIR="$2"
if [ "$ISSUE_NUM" = "601" ]; then
    exit 1  # Simulate crash
fi
sleep 1
WORKER
chmod +x "$CRASH_WORKER"

export AUTO_DEV_MAX_CONCURRENT=3
PIDS=()

dispatch_workers "$CRASH_WORKER" "601 602 603" PIDS

# Wait for all
ALL_EXIT=0
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || ALL_EXIT=$((ALL_EXIT + 1))
done

assert_eq "1" "$ALL_EXIT" "only 1 worker crashed, others succeeded"

rm -f "$CRASH_WORKER"

# --- Summary ---
print_summary
