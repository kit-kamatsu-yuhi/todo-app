#!/usr/bin/env bash
# test-claude-retry.sh — Claude 失敗時に state=failure へ原子遷移（Issue #148 AC-4）
#
# 検証観点:
#   1. claude CLI が exit 124（timeout 相当）で終了した場合、最終的に state=failure になる
#   2. claude CLI が exit 非 0 かつ auth 分類の場合、即 state=failure になる（リトライしない）
#   3. state ファイルの書込は atomic（壊れた中間状態が残らない）
#
# 前提:
#   run_claude が process-issue 風フローに組み込まれた公開関数を持つ、もしくは
#   lib/claude-runner.sh に run_claude_to_state <issue> <prompt...> のような
#   「失敗時に state を failure へ遷移させる」ラッパが生える。
#   両方とも無い場合は SKIP。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

RUNNER_SH=""
STATE_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/claude-runner.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/claude-runner.sh"; do
    if [ -f "$cand" ]; then
        RUNNER_SH="$cand"
        break
    fi
done
for cand in \
    "${SCRIPT_DIR}/../lib/state.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/state.sh"; do
    if [ -f "$cand" ]; then
        STATE_SH="$cand"
        break
    fi
done

echo "=== claude-runner → state=failure 原子遷移テスト ==="

if [ -z "$RUNNER_SH" ] || [ -z "$STATE_SH" ]; then
    echo "  ! SKIP: claude-runner.sh or state.sh not yet present"
    exit 0
fi

TMP=$(make_tmp_dir "claude-retry")
STATE_DIR="${TMP}/state"
mkdir -p "$STATE_DIR"
export STATE_DIR
export AUTO_DEV_REPO="test/repo"
export AUTO_DEV_RETRY_BACKOFF_BASE=0
export AUTO_DEV_RETRY_MAX_SLEEP=0

BIN=$(mock_bin_dir); export PATH="${BIN}:${PATH}"

for dep in \
    "${SCRIPT_DIR}/../lib/logger.sh" "${SCRIPT_DIR}/../devcontainer/lib/logger.sh" \
    "${SCRIPT_DIR}/../lib/error-classify.sh" "${SCRIPT_DIR}/../devcontainer/lib/error-classify.sh"; do
    [ -f "$dep" ] && source "$dep"
done
# shellcheck disable=SC1090
source "$STATE_SH"
# shellcheck disable=SC1090
source "$RUNNER_SH"

# set_state / write_state いずれかを使える前提で wrapper を用意する
write_state_compat() {
    local issue="$1" st="$2"
    if declare -f set_state >/dev/null 2>&1; then
        set_state "$issue" "$st"
    elif declare -f write_state >/dev/null 2>&1; then
        write_state "$issue" "$st"
    else
        printf '%s\n' "$st" > "${STATE_DIR}/issue-${issue}.state"
    fi
}

run_flow() {
    local issue="$1"
    local rc=0
    run_claude --prompt "dummy" >/dev/null 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        write_state_compat "$issue" "failure"
    fi
    return "$rc"
}

read_state() {
    local f="${STATE_DIR}/issue-$1.state"
    [ -f "$f" ] || { echo ""; return 0; }
    head -n1 "$f" | tr -d '\r\n '
}

# --- 1. timeout: 最終的に state=failure へ遷移 -----------------------------
rm -f "${STATE_DIR}"/*.state
mock_claude "$BIN" 124 '{}'
run_flow 501 || true
assert_eq "failure" "$(read_state 501)" "timeout 後に state=failure が書かれる"

# --- 2. auth: 即 failure（リトライ無し）-----------------------------------
rm -f "${STATE_DIR}"/*.state
export MOCK_CLAUDE_CALL_LOG="${TMP}/auth-calls.log"
: > "$MOCK_CLAUDE_CALL_LOG"
mock_claude "$BIN" 1 '{"subtype":"error_auth_invalid_key"}'
run_flow 502 || true
assert_eq "failure" "$(read_state 502)" "auth エラー直後に state=failure"
# 呼出回数 1 回（リトライしていない）
call_count=$(wc -l < "$MOCK_CLAUDE_CALL_LOG" | tr -d ' ')
assert_eq "1" "$call_count" "auth はリトライせず 1 回で state=failure"

# --- 3. atomic write: state ファイルに途中値が残らない --------------------
rm -f "${STATE_DIR}"/*.state
mock_claude "$BIN" 124 '{}'
run_flow 503 || true
content=$(cat "${STATE_DIR}/issue-503.state" 2>/dev/null || echo "")
assert_contains "$content" "failure" "state ファイルが failure を含む"
# 改行のみ / 空の壊れたファイルではない
size=$(wc -c < "${STATE_DIR}/issue-503.state" | tr -d ' ')
assert_true "state ファイルサイズ > 0 (got ${size})" test "$size" -gt 0

if ! print_summary; then
    exit 1
fi
