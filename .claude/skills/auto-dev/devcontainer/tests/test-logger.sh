#!/usr/bin/env bash
# test-logger.sh — lib/logger.sh の secret masking と JSON 出力検証（Issue #148 AC-6）
#
# 検証観点:
#   1. ANTHROPIC_API_KEY / GITHUB_TOKEN の値が出力に露出せず "***" にマスクされる
#   2. 出力行が 1 行 1 JSON object であり、jq で parse 可能
#   3. with_duration ラッパを呼ぶと ms 単位の duration フィールドが載る
#   4. 想定しない未知の token は masking 対象外（過剰マスク防止）
#
# 契約:
#   lib/logger.sh は以下関数を提供する:
#     log_event <level> <event_name> [key=value ...]
#       → stdout に JSON 1 行（AUTO_DEV_LOG_FILE 指定時はそちらにも append）
#     with_duration <event_name> <cmd...>
#       → cmd 実行し duration_ms を含む JSON を出す。exit code は cmd に従う。
#   secret masking 対象の env 変数:
#     ANTHROPIC_API_KEY / GITHUB_TOKEN / GH_TOKEN / OPENAI_API_KEY
#   fallback として logger.sh 未配備時は skip する（parallel TDD）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

LOGGER_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/logger.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/logger.sh"; do
    if [ -f "$cand" ]; then
        LOGGER_SH="$cand"
        break
    fi
done

echo "=== lib/logger.sh tests ==="

if [ -z "$LOGGER_SH" ]; then
    echo "  ! SKIP: lib/logger.sh not yet present (expected RED during parallel TDD)"
    echo "  (searched: ../lib/logger.sh, ../devcontainer/lib/logger.sh)"
    exit 0
fi

TMP=$(make_tmp_dir "logger-test")
LOG_FILE="${TMP}/out.jsonl"
export AUTO_DEV_LOG_FILE="$LOG_FILE"

# 意図的に「漏れるとまずい値」を env にセットする
export ANTHROPIC_API_KEY="sk-ant-xxxxxxxxxxxxxxxx-should-not-leak"
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx-should-not-leak"

# shellcheck disable=SC1090
source "$LOGGER_SH"

# --- 1. secret masking ------------------------------------------------------

: > "$LOG_FILE"
log_event info "test_event" "prompt=using key ${ANTHROPIC_API_KEY} now" "token=${GITHUB_TOKEN}" >/dev/null 2>&1 || true

assert_file_exists "$LOG_FILE" "log file is created"
assert_file_not_contains "$LOG_FILE" 'sk-ant-xxxxxxxxxxxxxxxx-should-not-leak' "ANTHROPIC_API_KEY 生値が漏れない"
assert_file_not_contains "$LOG_FILE" 'ghp_xxxxxxxxxxxxxxxxxxxx-should-not-leak' "GITHUB_TOKEN 生値が漏れない"
assert_file_contains "$LOG_FILE" '\*\*\*' "マスク文字列 *** が含まれる"

# --- 2. JSON validity -------------------------------------------------------

while IFS= read -r line; do
    [ -n "$line" ] || continue
    assert_json_valid "$line" "ログ行が JSON として valid"
done < "$LOG_FILE"

# --- 3. with_duration ラッパ ------------------------------------------------

: > "$LOG_FILE"
if declare -f with_duration >/dev/null 2>&1; then
    with_duration "sleep_event" sleep 0.05 >/dev/null 2>&1 || true
    assert_file_contains "$LOG_FILE" 'duration_ms' "with_duration は duration_ms を出す"
    if command -v jq >/dev/null 2>&1; then
        # duration_ms が 0 以上の数値
        last_dur=$(jq -r 'select(.duration_ms != null) | .duration_ms' "$LOG_FILE" | tail -n1)
        if [[ "$last_dur" =~ ^[0-9]+$ ]]; then
            assert_true "duration_ms が数値 (${last_dur})" true
        else
            assert_true "duration_ms が数値 (got: ${last_dur})" false
        fi
    fi
else
    echo "  ! with_duration が未定義（契約違反）"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("with_duration must be defined")
fi

# --- 4. 過剰マスクしない ---------------------------------------------------

: > "$LOG_FILE"
log_event info "benign_event" "note=this is fine" >/dev/null 2>&1 || true
assert_file_contains "$LOG_FILE" 'this is fine' "機密でない値は素通し"

if ! print_summary; then
    exit 1
fi
