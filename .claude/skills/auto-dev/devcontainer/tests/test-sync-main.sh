#!/bin/bash
# Tests for sync_main() and merge_main_into_current() functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/test-helper.sh"

# sync_main / merge_main_into_current reference $BASE_BRANCH at runtime.
# Tests use a bare repo with the default branch "main", so pin it here.
BASE_BRANCH="main"
export BASE_BRANCH

# Setup: create a temporary git repo for testing
WORK_DIR=$(mktemp -d)
REMOTE_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$WORK_DIR" "$REMOTE_DIR"
}
trap cleanup EXIT

# Create a bare "remote" repo
setup_remote() {
    git init --bare --initial-branch=main "$REMOTE_DIR/repo.git" >/dev/null 2>&1
}

# Clone and set up the "local" repo
setup_local() {
    git clone "$REMOTE_DIR/repo.git" "$WORK_DIR/local" >/dev/null 2>&1
    cd "$WORK_DIR/local"
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "initial" > file.txt
    git add file.txt
    git commit -m "initial" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
}

# Source the functions under test
# We need LIB_DIR to be set for sourcing
source_functions() {
    cd "$WORK_DIR/local"
    # Source only the sync functions from process-issue.sh
    # We extract them to avoid running the main script logic
    local lib_dir
    lib_dir="$(cd "${SCRIPT_DIR}/../lib" && pwd)"

    # Check that sync_main function exists in process-issue.sh
    if grep -q "^sync_main()" "${lib_dir}/process-issue.sh"; then
        # Extract just the functions we need
        eval "$(sed -n '/^sync_main()/,/^}/p' "${lib_dir}/process-issue.sh")"
        eval "$(sed -n '/^merge_main_into_current()/,/^}/p' "${lib_dir}/process-issue.sh")"
        return 0
    else
        return 1
    fi
}

# ===========================================
# Tests
# ===========================================

echo "=== sync_main / merge_main_into_current tests ==="

setup_remote
setup_local

# --- Test 1: sync_main fetches latest from origin/main ---
echo ""
echo "--- sync_main fetches latest ---"

# Make a new commit on remote (simulate another worker pushing)
cd "$WORK_DIR/local"
git checkout -b feature/test >/dev/null 2>&1

# Push a new commit directly to remote's main
SECOND_CLONE=$(mktemp -d)
git clone "$REMOTE_DIR/repo.git" "$SECOND_CLONE/repo" >/dev/null 2>&1
cd "$SECOND_CLONE/repo"
git config user.email "test@test.com"
git config user.name "Test"
echo "remote-change" > remote-file.txt
git add remote-file.txt
git commit -m "remote commit" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

# Back to local - origin/main should be old
cd "$WORK_DIR/local"
OLD_REV=$(git rev-parse origin/main 2>/dev/null)

# Source and run sync_main
if source_functions; then
    sync_main
    NEW_REV=$(git rev-parse origin/main 2>/dev/null)
    assert_true "sync_main updates origin/main ref" [ "$OLD_REV" != "$NEW_REV" ]
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("sync_main function not found in process-issue.sh")
    echo "  ✗ sync_main function not found in process-issue.sh"
fi

# --- Test 2: sync_main does not crash when fetch fails ---
echo ""
echo "--- sync_main tolerates fetch failure ---"

cd "$WORK_DIR/local"
if source_functions; then
    # Point to a non-existent remote temporarily
    git remote set-url origin /nonexistent/path
    sync_main  # Should not crash due to || true
    assert_eq "0" "$?" "sync_main returns 0 even when fetch fails"
    # Restore remote
    git remote set-url origin "$REMOTE_DIR/repo.git"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("sync_main function not found")
    echo "  ✗ sync_main function not found"
fi

# --- Test 3: merge_main_into_current succeeds with no conflicts ---
echo ""
echo "--- merge_main_into_current succeeds (no conflict) ---"

cd "$WORK_DIR/local"
git remote set-url origin "$REMOTE_DIR/repo.git"
git fetch origin main >/dev/null 2>&1

if source_functions; then
    git checkout feature/test >/dev/null 2>&1
    merge_main_into_current
    EXIT_CODE=$?
    assert_eq "0" "$EXIT_CODE" "merge_main_into_current returns 0 on clean merge"

    # Verify the remote file is now in our branch
    assert_true "merged file exists in feature branch" [ -f "remote-file.txt" ]
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("merge_main_into_current function not found")
    echo "  ✗ merge_main_into_current function not found"
fi

# --- Test 4: merge_main_into_current returns non-zero on conflict ---
echo ""
echo "--- merge_main_into_current fails on conflict ---"

cd "$WORK_DIR/local"
# Create a conflicting change on main via remote
cd "$SECOND_CLONE/repo"
echo "main-version" > conflict-file.txt
git add conflict-file.txt
git commit -m "main conflict" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

# Create the same file with different content on feature branch
cd "$WORK_DIR/local"
git checkout feature/test >/dev/null 2>&1
echo "feature-version" > conflict-file.txt
git add conflict-file.txt
git commit -m "feature conflict" >/dev/null 2>&1
git fetch origin main >/dev/null 2>&1

if source_functions; then
    set +e
    merge_main_into_current
    EXIT_CODE=$?
    set -e
    assert_true "merge_main_into_current returns non-zero on conflict" [ "$EXIT_CODE" -ne 0 ]
    # Clean up the failed merge
    git merge --abort 2>/dev/null || true
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("merge_main_into_current function not found")
    echo "  ✗ merge_main_into_current function not found"
fi

# Cleanup second clone
rm -rf "$SECOND_CLONE"

# --- Print summary ---
print_summary
