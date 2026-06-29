#!/bin/bash
# Worker wrapper: runs process-issue.sh with crash handling.
#
# Ensures lock release, worktree removal, and failure notification on any exit.
# Each worker operates in its own git worktree to avoid concurrent checkout
# conflicts on the shared working tree.
#
# Changes from Issue #148 (T7):
#   - trap now also terminates child process groups so long-running claude CLI
#     calls cannot leak past worker exit
#   - worktree cleanup is idempotent and survives repeated signals

set -uo pipefail

ISSUE_NUM="${1:-${ISSUE_NUM:-}}"
STATE_DIR="${2:-${STATE_DIR:-/var/auto-dev/state}}"
LOG_DIR="${LOG_DIR:-/var/auto-dev/logs}"

# Resolve LIB_DIR. Prefer the container install, fall back to the directory
# that ships with this script so unit tests can source individual helpers.
if [ -z "${LIB_DIR:-}" ]; then
    if [ -d "/usr/local/lib/auto-dev" ] && [ -f "/usr/local/lib/auto-dev/logger.sh" ]; then
        LIB_DIR="/usr/local/lib/auto-dev"
    else
        LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi

if [ -n "$ISSUE_NUM" ]; then
    WORKER_LOG="${LOG_DIR}/worker-${ISSUE_NUM}-$(date +%Y%m%d-%H%M%S).log"
else
    WORKER_LOG="${LOG_DIR}/worker-$(date +%Y%m%d-%H%M%S).log"
fi

REPO_DIR="${AUTO_DEV_REPO_DIR:-/workspace/repo}"
WORKTREE_ROOT="${AUTO_DEV_WORKTREE_ROOT:-/workspace/worktrees}"
WORKTREE_DIR="${WORKTREE_ROOT}/issue-${ISSUE_NUM}"

export ISSUE_NUM STATE_DIR LOG_DIR AUTO_DEV_REPO REPO_DIR WORKTREE_DIR LIB_DIR

# shellcheck disable=SC1091
source "${LIB_DIR}/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/notify.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/git-base.sh"

BASE_BRANCH="${BASE_BRANCH:-$(detect_base_branch "$REPO_DIR")}"
export BASE_BRANCH

CHILD_PID=""

cleanup_worktree() {
    if [ -d "$WORKTREE_DIR" ]; then
        git -C "$REPO_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null \
            || rm -rf "$WORKTREE_DIR"
    fi
    git -C "$REPO_DIR" worktree prune 2>/dev/null || true
}

# Kill the child process group if still alive. Safe on empty / dead PIDs.
kill_child_tree() {
    local pid="${1:-}"
    if [ -z "$pid" ]; then
        return 0
    fi
    if kill -0 "$pid" 2>/dev/null; then
        # Try TERM first, then KILL. Use the process group so timeout's child
        # chain (claude / codex) also dies.
        kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
        sleep 1 &
        wait $! 2>/dev/null || true
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
}

# Crash handler: kill children, release lock, cleanup worktree, notify.
# The failure comment combines the error notice and the retry guidance into a
# single message so the Issue thread is not spammed with two separate posts.
on_worker_exit() {
    local exit_code=$?
    kill_child_tree "$CHILD_PID" 2>/dev/null || true

    if [ "$exit_code" -ne 0 ]; then
        echo "[worker] Issue #${ISSUE_NUM}: crashed with exit code ${exit_code}" | tee -a "$WORKER_LOG"
        log_error "worker_crashed" issue="$ISSUE_NUM" exit_code="$exit_code" 2>/dev/null || true
        local failure_message
        failure_message="⚠️ auto-dev: 処理中にエラーが発生しました (exit code: ${exit_code})"$'\n\n'"再実行するには、この Issue に新しいコメントを投稿してください。"
        notify_github_comment "$ISSUE_NUM" "$failure_message" 2>/dev/null || true
        set_issue_state "$ISSUE_NUM" "failure" 2>/dev/null || true
    fi
    unlock_issue "$ISSUE_NUM" 2>/dev/null || true
    cleanup_worktree 2>/dev/null || true
}
trap on_worker_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# When sourced without an ISSUE_NUM (unit tests that exercise cleanup via a
# harness), stop here so the worktree / lock / child-spawn block is skipped.
if [ -z "${ISSUE_NUM:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

echo "[worker] Issue #${ISSUE_NUM}: starting (PID $$)" | tee -a "$WORKER_LOG"
log_info "worker_start" issue="$ISSUE_NUM" pid="$$" worktree="$WORKTREE_DIR" 2>/dev/null || true

# Acquire lock
if ! lock_issue "$ISSUE_NUM"; then
    echo "[worker] Issue #${ISSUE_NUM}: failed to acquire lock, skipping" | tee -a "$WORKER_LOG"
    trap - EXIT
    exit 0
fi

# --- Setup per-worker worktree ---
mkdir -p "$WORKTREE_ROOT"

# Remove stale worktree from previous run
if [ -d "$WORKTREE_DIR" ]; then
    git -C "$REPO_DIR" worktree remove --force "$WORKTREE_DIR" 2>/dev/null \
        || rm -rf "$WORKTREE_DIR"
fi
git -C "$REPO_DIR" worktree prune 2>/dev/null || true

# Ensure origin/$BASE_BRANCH is fresh
git -C "$REPO_DIR" fetch origin "$BASE_BRANCH" 2>/dev/null || true

# Create worktree detached at origin/$BASE_BRANCH; process-issue.sh will
# checkout/create the appropriate branch based on phase.
if ! git -C "$REPO_DIR" worktree add --detach "$WORKTREE_DIR" "origin/${BASE_BRANCH}" 2>&1 | tee -a "$WORKER_LOG"; then
    echo "[worker] Issue #${ISSUE_NUM}: failed to create worktree" | tee -a "$WORKER_LOG"
    exit 1
fi

echo "[worker] Issue #${ISSUE_NUM}: worktree ${WORKTREE_DIR}" | tee -a "$WORKER_LOG"

# Run the actual issue processor with timeout, from within the worktree.
# setsid で子プロセスを新しい process group として起動することで、
# `kill -TERM -$CHILD_PID` が claude / codex など孫プロセスにも SIGTERM を伝播できる。
# setsid が無い環境 (macOS デフォルト等) では foreground 指定の timeout で代用する。
WORKER_TIMEOUT="${AUTO_DEV_WORKER_TIMEOUT:-1800}"
if command -v setsid >/dev/null 2>&1; then
    setsid bash -c "cd \"$WORKTREE_DIR\" && timeout --signal=TERM --foreground \"$WORKER_TIMEOUT\" \"${LIB_DIR}/process-issue.sh\" \"$ISSUE_NUM\"" \
        >> "$WORKER_LOG" 2>&1 &
else
    (
        cd "$WORKTREE_DIR"
        timeout --signal=TERM --foreground "$WORKER_TIMEOUT" \
            "${LIB_DIR}/process-issue.sh" "$ISSUE_NUM"
    ) >> "$WORKER_LOG" 2>&1 &
fi
CHILD_PID=$!

wait "$CHILD_PID"
EXIT_CODE=$?
CHILD_PID=""

if [ "$EXIT_CODE" -eq 124 ]; then
    echo "[worker] Issue #${ISSUE_NUM}: timed out after ${WORKER_TIMEOUT}s" >> "$WORKER_LOG"
    log_warn "worker_timeout" issue="$ISSUE_NUM" timeout_s="$WORKER_TIMEOUT" 2>/dev/null || true
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[worker] Issue #${ISSUE_NUM}: completed successfully" >> "$WORKER_LOG"
    log_info "worker_done" issue="$ISSUE_NUM" 2>/dev/null || true
fi

exit "$EXIT_CODE"
