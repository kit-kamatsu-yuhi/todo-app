#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/test-helper.sh"

# Setup temp state dir for tests
TEST_STATE_DIR=$(mktemp -d)
export STATE_DIR="$TEST_STATE_DIR"
export AUTO_DEV_LOCK_TTL=5

# Source the module under test
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
source "${LIB_DIR}/state.sh"

cleanup() { rm -rf "$TEST_STATE_DIR"; }
trap cleanup EXIT

echo "=== state.sh tests ==="

# --- Lock acquire/release ---

echo ""
echo "Lock acquire/release:"

lock_issue "100"
assert_true "lock_issue creates lock directory" [ -d "${STATE_DIR}/issue-100.lock.d" ]
assert_true "lock_issue writes PID" [ -f "${STATE_DIR}/issue-100.lock.d/pid" ]
assert_true "lock_issue writes timestamp" [ -f "${STATE_DIR}/issue-100.lock.d/timestamp" ]

assert_true "is_issue_locked returns true for locked issue" is_issue_locked "100"

unlock_issue "100"
assert_false "is_issue_locked returns false after unlock" is_issue_locked "100"
assert_false "unlock removes lock directory" [ -d "${STATE_DIR}/issue-100.lock.d" ]

# --- Lock prevents duplicate ---

echo ""
echo "Lock prevents duplicate:"

lock_issue "200"
assert_true "first lock succeeds" is_issue_locked "200"

# Second lock attempt should fail
if lock_issue "200" 2>/dev/null; then
    assert_eq "fail" "success" "duplicate lock should fail"
else
    assert_eq "0" "0" "duplicate lock correctly rejected"
fi

unlock_issue "200"

# --- Lock TTL expiry ---

echo ""
echo "Lock TTL expiry:"

export AUTO_DEV_LOCK_TTL=1
source "${LIB_DIR}/state.sh"

lock_issue "300"
assert_true "lock exists before TTL" is_issue_locked "300"

sleep 2

assert_false "lock expired after TTL" is_issue_locked "300"

# --- State management ---

echo ""
echo "State management:"

set_issue_state "400" "implementing"
assert_eq "implementing" "$(get_issue_state '400')" "get_issue_state returns set value"

set_issue_state "400" "merged"
assert_true "is_issue_completed returns true for merged" is_issue_completed "400"

set_issue_state "401" "failure"
assert_true "is_issue_completed treats failure as completed when no new activity" is_issue_completed "401"

assert_false "is_issue_completed returns false for unknown" is_issue_completed "999"

# --- Failure retry on new activity ---

echo ""
echo "Failure retry on new activity:"

# Backdate the state file and stub gh so activity timestamp is newer.
set_issue_state "402" "failure"
touch -d "2020-01-01 00:00:00" "${STATE_DIR}/issue-402.state"

gh() {
    echo "2030-01-01T00:00:00Z"
}
export -f gh
export AUTO_DEV_REPO="test/repo"

assert_false "is_issue_completed returns false when activity newer than state mtime" \
    is_issue_completed "402"

unset -f gh

# --- Summary ---
print_summary
