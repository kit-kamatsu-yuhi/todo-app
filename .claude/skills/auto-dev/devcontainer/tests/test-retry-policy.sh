#!/usr/bin/env bash
# test-retry-policy.sh — lib/claude-runner.sh の分類別 retry 戦略（Issue #148 AC-17）
#
# 期待動作:
#   auth / billing / context_overflow → リトライ無し（claude 呼出 1 回）
#   rate_limit / timeout              → 最大 2 回リトライ（合計 3 回呼出）
#   unknown                           → 1 回リトライ（合計 2 回呼出）
#
# 検証戦略:
#   PATH に mock claude を配置し、呼出ごとに call log に 1 行追記する。
#   run_claude を実行した後、call log の行数で呼出回数を確認する。
#   mock claude は常に固定の JSON を返し、固定の exit code で終了する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

RUNNER_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/claude-runner.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/claude-runner.sh"; do
    if [ -f "$cand" ]; then
        RUNNER_SH="$cand"
        break
    fi
done

echo "=== lib/claude-runner.sh retry policy tests ==="

if [ -z "$RUNNER_SH" ]; then
    echo "  ! SKIP: lib/claude-runner.sh not yet present (expected RED during parallel TDD)"
    exit 0
fi

TMP=$(make_tmp_dir "retry-test")
BIN=$(mock_bin_dir); export PATH="${BIN}:${PATH}"

# 先行依存をロード（存在するものだけ）
for dep in \
    "${SCRIPT_DIR}/../lib/logger.sh" "${SCRIPT_DIR}/../devcontainer/lib/logger.sh" \
    "${SCRIPT_DIR}/../lib/error-classify.sh" "${SCRIPT_DIR}/../devcontainer/lib/error-classify.sh"; do
    [ -f "$dep" ] && source "$dep"
done
# shellcheck disable=SC1090
source "$RUNNER_SH"

if ! declare -f run_claude >/dev/null 2>&1; then
    echo "  ! FAIL: run_claude function is not defined"
    exit 1
fi

# リトライ中の sleep を短縮するテスト用フック（実装側が参照する想定）
export AUTO_DEV_RETRY_BACKOFF_BASE=0
export AUTO_DEV_RETRY_MAX_SLEEP=0

# 毎ケース前に call log をリセットする
reset_mock() {
    local exit_code="$1" stdout_json="$2"
    export MOCK_CLAUDE_CALL_LOG="${TMP}/calls.log"
    : > "$MOCK_CLAUDE_CALL_LOG"
    mock_claude "$BIN" "$exit_code" "$stdout_json"
}

count_calls() {
    wc -l < "$MOCK_CLAUDE_CALL_LOG" | tr -d ' '
}

# --- auth: リトライ無し (1 回) ---------------------------------------------
reset_mock 1 '{"subtype":"error_auth_invalid_key"}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "1" "$(count_calls)" "auth: 1 回だけ呼ばれる（リトライ無し）"

# --- billing: リトライ無し -------------------------------------------------
reset_mock 1 '{"subtype":"error_max_budget_usd"}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "1" "$(count_calls)" "billing: 1 回だけ呼ばれる"

# --- context_overflow: リトライ無し ----------------------------------------
reset_mock 1 '{"subtype":"error_max_tokens"}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "1" "$(count_calls)" "context_overflow: 1 回だけ呼ばれる"

# --- rate_limit: 最大 2 回リトライ (合計 3 回) -----------------------------
reset_mock 1 '{"subtype":"error_rate_limit"}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "3" "$(count_calls)" "rate_limit: 最大 2 回リトライ（合計 3 回呼出）"

# --- timeout: 最大 2 回リトライ (合計 3 回) -------------------------------
reset_mock 124 '{}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "3" "$(count_calls)" "timeout: 最大 2 回リトライ（合計 3 回呼出）"

# --- unknown: 1 回リトライ (合計 2 回) -------------------------------------
reset_mock 1 '{}'
run_claude --prompt "dummy" >/dev/null 2>&1 || true
assert_eq "2" "$(count_calls)" "unknown: 1 回リトライ（合計 2 回呼出）"

if ! print_summary; then
    exit 1
fi
