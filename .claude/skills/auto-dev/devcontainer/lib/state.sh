#!/bin/bash
# State management for auto-dev issue processing
#
# States:
#   (none)          → Issue未処理
#   plan-posted     → プラン投稿済み、ユーザー承認待ち
#   implementing    → 実装中
#   pr-created      → PR作成済み、レビュー待ち
#   merged          → マージ完了
#   failure         → エラー終了（次回スキャン時に Issue の最終活動 TS と比較して再処理判定）
#
# Changes from Issue #148:
#   - set_issue_state を mv -T で atomic write 化
#   - lock_issue/is_issue_locked に PID 生存確認（kill -0）を追加
#   - clean_stale_locks を追加（起動時の stale lock 掃除用）

STATE_DIR="${STATE_DIR:-/var/auto-dev/state}"
LOCK_TTL_SECONDS="${AUTO_DEV_LOCK_TTL:-3600}"

# --- Lock (atomic mkdir + PID liveness) ---

is_issue_locked() {
    local issue_num="$1"
    local lock_dir="${STATE_DIR}/issue-${issue_num}.lock.d"

    if [ ! -d "$lock_dir" ]; then
        return 1
    fi

    local ts_file="${lock_dir}/timestamp"
    local pid_file="${lock_dir}/pid"

    # Missing metadata → broken lock, remove.
    if [ ! -f "$ts_file" ]; then
        rm -rf "$lock_dir"
        return 1
    fi

    # PID liveness check: if the pid file exists and the process is gone,
    # the lock is stale regardless of TTL.
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            echo "[state] Stale lock for issue #${issue_num} (pid ${pid} not alive)" >&2
            rm -rf "$lock_dir"
            return 1
        fi
    fi

    local lock_time now elapsed
    lock_time=$(cat "$ts_file" 2>/dev/null || echo "0")
    now=$(date +%s)
    elapsed=$(( now - lock_time ))

    if [ "$elapsed" -gt "$LOCK_TTL_SECONDS" ]; then
        echo "[state] Lock expired for issue #${issue_num} (${elapsed}s > ${LOCK_TTL_SECONDS}s)" >&2
        rm -rf "$lock_dir"
        return 1
    fi

    return 0
}

lock_issue() {
    local issue_num="$1"
    local lock_dir="${STATE_DIR}/issue-${issue_num}.lock.d"

    # First try an atomic mkdir. In the happy path this is the only syscall
    # needed and wins the race against other processes trivially.
    if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "${lock_dir}/pid"
        date +%s > "${lock_dir}/timestamp"
        return 0
    fi

    # mkdir failed → either a live owner holds the lock, or it is stale /
    # broken. Check the pid file to decide. A live owner MUST have a pid
    # file by the time another process sees its lock_dir (race window
    # between `mkdir` and `printf > pid` is tiny: pid write happens before
    # timestamp write, so we look at pid first).
    local pid_file="${lock_dir}/pid"
    local pid=""
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file" 2>/dev/null || echo "")
    fi

    # If pid is missing entirely, the lock is half-initialized by a live
    # competitor (they won mkdir moments ago and are about to write pid).
    # Back off without clearing so we don't steal a live lock.
    if [ -z "$pid" ]; then
        return 1
    fi

    # Alive pid → active lock; back off.
    if kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Dead pid → stale. Clear and retry once. If the retry races with a
    # concurrent stale-sweeper, one of us wins and the other returns 1.
    echo "[state] Stale lock for issue #${issue_num} (pid ${pid} not alive); clearing and retrying" >&2
    rm -rf "$lock_dir"
    if mkdir "$lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "${lock_dir}/pid"
        date +%s > "${lock_dir}/timestamp"
        return 0
    fi
    return 1
}

unlock_issue() {
    local issue_num="$1"
    rm -rf "${STATE_DIR}/issue-${issue_num}.lock.d"
}

# Sweep any lock directories whose owning process is gone.
# Called from entrypoint.sh on startup to recover from ungraceful shutdown.
clean_stale_locks() {
    local dir pid
    shopt -s nullglob
    for dir in "${STATE_DIR}"/issue-*.lock.d; do
        [ -d "$dir" ] || continue
        if [ -f "${dir}/pid" ]; then
            pid=$(cat "${dir}/pid" 2>/dev/null || echo "")
            if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
                echo "[state] Removing stale lock: ${dir} (pid=${pid:-unknown})" >&2
                rm -rf "$dir"
            fi
        else
            # No pid file means broken lock from an older version.
            echo "[state] Removing broken lock (no pid): ${dir}" >&2
            rm -rf "$dir"
        fi
    done
    shopt -u nullglob
}

# --- State (atomic write) ---

get_issue_state() {
    local issue_num="$1"
    local state_file="${STATE_DIR}/issue-${issue_num}.state"
    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        echo ""
    fi
}

# Atomic write: write to a temp file in the same dir, then mv -T (no-target-
# directory) to replace atomically. Requires GNU coreutils (Debian-based
# container image). Falls back to a plain mv on rare systems that reject -T.
set_issue_state() {
    local issue_num="$1"
    local state="$2"
    local state_file="${STATE_DIR}/issue-${issue_num}.state"
    local tmp
    tmp=$(mktemp "${STATE_DIR}/.issue-${issue_num}.state.XXXXXX") || {
        echo "[state] failed to allocate tmp state file" >&2
        return 1
    }
    printf '%s\n' "$state" > "$tmp"
    if ! mv -T "$tmp" "$state_file" 2>/dev/null; then
        mv -f "$tmp" "$state_file" || {
            rm -f "$tmp" 2>/dev/null || true
            echo "[state] failed to install state file" >&2
            return 1
        }
    fi
    echo "[state] Issue #${issue_num} → ${state}" >&2
}

# --- Timestamp helpers for failure-retry judgement ---

# Return the state file mtime in epoch seconds.
# Prints 0 when the file does not exist. Linux / GNU coreutils only.
get_state_file_mtime() {
    local issue_num="$1"
    local normalized
    normalized=$(printf '%d' "$issue_num" 2>/dev/null) || normalized=0
    local state_file="${STATE_DIR}/issue-${normalized}.state"

    if [ ! -f "$state_file" ]; then
        echo 0
        return 0
    fi

    local mtime
    mtime=$(stat -c %Y "$state_file" 2>/dev/null || echo 0)
    if [ -z "$mtime" ]; then
        mtime=0
    fi
    echo "$mtime"
}

# Return the latest activity timestamp of the issue in epoch seconds.
get_issue_last_activity() {
    local issue_num="$1"
    local normalized
    normalized=$(printf '%d' "$issue_num" 2>/dev/null) || normalized=0

    local repo="${AUTO_DEV_REPO:-}"
    if [ -z "$repo" ]; then
        echo 0
        return 0
    fi

    local ts
    ts=$(gh issue view "$normalized" \
            --repo "$repo" \
            --json updatedAt \
            --jq '.updatedAt // empty' 2>/dev/null || echo "")

    if [ -z "$ts" ]; then
        echo 0
        return 0
    fi

    local epoch
    epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
    if [ -z "$epoch" ]; then
        epoch=0
    fi
    echo "$epoch"
}

# Returns 0 when the issue should be treated as "completed" and skipped.
# Returns non-zero when the issue still needs processing.
is_issue_completed() {
    local issue_num="$1"
    local state
    state=$(get_issue_state "$issue_num")

    case "$state" in
        merged)
            return 0
            ;;
        failure)
            local state_mtime activity_ts
            state_mtime=$(get_state_file_mtime "$issue_num")
            activity_ts=$(get_issue_last_activity "$issue_num")

            if [ "$activity_ts" -gt "$state_mtime" ]; then
                echo "[state] Issue #${issue_num}: failure but new activity detected (retrying)" >&2
                return 1
            fi

            echo "[state] Issue #${issue_num}: failed previously, awaiting new activity" >&2
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
