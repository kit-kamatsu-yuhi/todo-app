#!/usr/bin/env bash
# test_state.sh — state.sh ユニットテスト（Issue #144）
#
# 実行方法:
#   bash exoloop/.claude/skills/auto-dev/tests/test_state.sh
#
# 前提:
#   - bash 5 系（Linux / devcontainer を想定。macOS は非対応）
#   - GNU date（date -d <ISO8601> +%s）
#   - GNU stat（stat -c %Y）
#   - `gh` はテスト内でシェル関数としてスタブ化するため実 CLI は不要
#
# 契約:
#   state.sh が以下 3 関数を export し、STATE_DIR / AUTO_DEV_REPO 環境変数で挙動を差し替えられること。
#     - get_state_file_mtime <issue_num>   → stdout に epoch 秒、ファイル無しで "0"
#     - get_issue_last_activity <issue_num> → gh issue view --json updatedAt を epoch 秒化、失敗時 "0"
#     - is_issue_completed <issue_num>      → merged で 0、failure かつ activity > mtime で 1、その他の failure で 0

set -uo pipefail

# --- パス解決 ----------------------------------------------------------------

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve state.sh across both layouts:
#   - exoloop subtree: tests/../devcontainer/lib/state.sh
#   - consumer repo:       tests/../lib/state.sh
STATE_SH=""
for candidate in \
    "${TEST_DIR}/../devcontainer/lib/state.sh" \
    "${TEST_DIR}/../lib/state.sh"; do
    if [ -f "$candidate" ]; then
        STATE_SH="$candidate"
        break
    fi
done

if [ -z "$STATE_SH" ]; then
    echo "FATAL: state.sh not found (checked ../devcontainer/lib and ../lib)" >&2
    exit 2
fi

# --- 一時ディレクトリと環境変数 ---------------------------------------------

STATE_DIR="$(mktemp -d -t auto-dev-state-XXXXXX)"
export STATE_DIR
export AUTO_DEV_REPO="test/repo"

cleanup() {
    rm -rf "$STATE_DIR"
}
trap cleanup EXIT

# shellcheck disable=SC1090
source "$STATE_SH"

# --- アサーションヘルパー ---------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

assert_equals() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-values differ}"
    if [ "$expected" != "$actual" ]; then
        echo "  FAIL: ${msg}: expected='${expected}' actual='${actual}'" >&2
        return 1
    fi
    return 0
}

# 戻り値を検証する。期待する終了コードと実際のコードを比較する。
assert_exit() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-exit code differs}"
    if [ "$expected" != "$actual" ]; then
        echo "  FAIL: ${msg}: expected=${expected} actual=${actual}" >&2
        return 1
    fi
    return 0
}

run_test() {
    local name="$1"
    local fn="$2"
    TOTAL_COUNT=$(( TOTAL_COUNT + 1 ))

    # 各テストの前に state ディレクトリを空にする
    rm -rf "$STATE_DIR"
    mkdir -p "$STATE_DIR"

    # gh スタブはデフォルトで「呼ばれたら失敗」。各テストで必要なら上書きする。
    gh() {
        echo "gh stub: unexpected call: $*" >&2
        return 1
    }
    export -f gh

    if "$fn"; then
        echo "PASS: $name"
        PASS_COUNT=$(( PASS_COUNT + 1 ))
    else
        echo "FAIL: $name"
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    fi
}

# --- テストケース -----------------------------------------------------------

# 1. state ファイル未設定 → is_issue_completed は「未完了」（非ゼロ）
test_no_state_file_not_completed() {
    is_issue_completed 999
    local rc=$?
    assert_exit 1 "$rc" "no state file should be treated as not completed" || return 1
}

# 2. state=merged → 完了扱い（0）
test_merged_is_completed() {
    echo "merged" > "${STATE_DIR}/issue-1.state"
    is_issue_completed 1
    local rc=$?
    assert_exit 0 "$rc" "merged should be completed" || return 1
}

# 3. state=failure、最終活動が state mtime より古い → skip（0）
test_failure_no_new_activity_skip() {
    local state_file="${STATE_DIR}/issue-2.state"
    echo "failure" > "$state_file"
    # state mtime = 現在
    touch -d "@$(date +%s)" "$state_file"

    # gh スタブ: 過去時刻を返す（実装は --jq '.updatedAt // empty' で ISO8601 文字列を受け取る）
    gh() {
        echo '2020-01-01T00:00:00Z'
    }
    export -f gh

    is_issue_completed 2
    local rc=$?
    assert_exit 0 "$rc" "failure + old activity should be skipped (completed)" || return 1
}

# 4. state=failure、最終活動が state mtime より新しい → 再処理候補（非ゼロ）
test_failure_with_new_activity_retry() {
    local state_file="${STATE_DIR}/issue-3.state"
    echo "failure" > "$state_file"
    # state mtime を 1時間前に後退させる
    local past=$(( $(date +%s) - 3600 ))
    touch -d "@${past}" "$state_file"

    # gh スタブ: 現在時刻（＝state mtime より新しい）を ISO8601 で返す
    local now_iso
    now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    export now_iso
    gh() {
        printf '%s\n' "$now_iso"
    }
    export -f gh

    is_issue_completed 3
    local rc=$?
    assert_exit 1 "$rc" "failure + new activity should not be completed (retry)" || return 1
}

# 5. state=failure、gh が空 → activity_ts=0 で安全側に skip（0）
test_failure_gh_empty_safe_skip() {
    local state_file="${STATE_DIR}/issue-4.state"
    echo "failure" > "$state_file"
    touch -d "@$(date +%s)" "$state_file"

    gh() {
        # 空出力で失敗を模す
        echo ""
        return 1
    }
    export -f gh

    is_issue_completed 4
    local rc=$?
    assert_exit 0 "$rc" "failure + gh empty should be skipped (safe side)" || return 1
}

# 6. get_state_file_mtime は state ファイル不在時に "0" を出す
test_get_state_file_mtime_missing() {
    local out
    out=$(get_state_file_mtime 9999)
    assert_equals "0" "$out" "missing state file should yield mtime=0" || return 1
}

# --- 実行 -------------------------------------------------------------------

run_test "test_no_state_file_not_completed"       test_no_state_file_not_completed
run_test "test_merged_is_completed"               test_merged_is_completed
run_test "test_failure_no_new_activity_skip"      test_failure_no_new_activity_skip
run_test "test_failure_with_new_activity_retry"   test_failure_with_new_activity_retry
run_test "test_failure_gh_empty_safe_skip"        test_failure_gh_empty_safe_skip
run_test "test_get_state_file_mtime_missing"      test_get_state_file_mtime_missing

echo "Passed: ${PASS_COUNT} / Total: ${TOTAL_COUNT}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
