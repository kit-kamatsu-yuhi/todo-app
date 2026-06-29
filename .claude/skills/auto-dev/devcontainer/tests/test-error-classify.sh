#!/usr/bin/env bash
# test-error-classify.sh — lib/error-classify.sh の 6 分類判定（Issue #148 AC-16）
#
# 契約:
#   classify_error <exit_code> <stdout_json_or_path>
#     → stdout に分類名を 1 行で出す: auth / billing / rate_limit / context_overflow / timeout / unknown
#   判定優先順位:
#     1. subtype フィールドで確定（例: error_auth_invalid_key, error_max_budget_usd, error_rate_limit, error_max_tokens, error_context_overflow）
#     2. errors[] の文字列ヒット（例: "Reached maximum budget", "rate limit", "maximum budget exceeded"）
#     3. exit code ベース（124 / 137 → timeout, 429 → rate_limit）
#     4. JSON parse 失敗 or 該当なし → unknown

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

ECS_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/error-classify.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/error-classify.sh"; do
    if [ -f "$cand" ]; then
        ECS_SH="$cand"
        break
    fi
done

echo "=== lib/error-classify.sh tests ==="

if [ -z "$ECS_SH" ]; then
    echo "  ! SKIP: lib/error-classify.sh not yet present (expected RED during parallel TDD)"
    exit 0
fi

# logger.sh が先行依存なら load を試みる（無くても動作する契約）
for dep in "${SCRIPT_DIR}/../lib/logger.sh" "${SCRIPT_DIR}/../devcontainer/lib/logger.sh"; do
    [ -f "$dep" ] && source "$dep" && break || true
done

# shellcheck disable=SC1090
source "$ECS_SH"

if ! declare -f classify_error >/dev/null 2>&1; then
    echo "  ! FAIL: classify_error function is not defined"
    exit 1
fi

classify() {
    local exit_code="$1" payload="$2"
    classify_error "$exit_code" "$payload" 2>/dev/null | tr -d '\r\n '
}

# ---- auth (2 ケース) ------------------------------------------------------
assert_eq "auth" "$(classify 1 '{"subtype":"error_auth_invalid_key"}')" \
    "auth: subtype=error_auth_invalid_key"
assert_eq "auth" "$(classify 1 '{"subtype":"error_auth_expired"}')" \
    "auth: subtype=error_auth_expired"

# ---- billing (2 ケース) ---------------------------------------------------
assert_eq "billing" "$(classify 1 '{"subtype":"error_max_budget_usd","errors":["Reached maximum budget ($5)"]}')" \
    "billing: subtype=error_max_budget_usd"
assert_eq "billing" "$(classify 1 '{"errors":["maximum budget exceeded"]}')" \
    "billing: errors[] に maximum budget"

# ---- rate_limit (2 ケース) ------------------------------------------------
assert_eq "rate_limit" "$(classify 1 '{"subtype":"error_rate_limit"}')" \
    "rate_limit: subtype=error_rate_limit"
assert_eq "rate_limit" "$(classify 429 '{}')" \
    "rate_limit: exit code 429"

# ---- context_overflow (2 ケース) ------------------------------------------
assert_eq "context_overflow" "$(classify 1 '{"subtype":"error_max_tokens"}')" \
    "context_overflow: subtype=error_max_tokens"
assert_eq "context_overflow" "$(classify 1 '{"subtype":"error_context_overflow"}')" \
    "context_overflow: subtype=error_context_overflow"

# ---- timeout (2 ケース) ---------------------------------------------------
assert_eq "timeout" "$(classify 124 '{}')" \
    "timeout: exit code 124 (SIGTERM from parent)"
assert_eq "timeout" "$(classify 137 '{}')" \
    "timeout: exit code 137 (SIGKILL)"

# ---- unknown (2 ケース) ---------------------------------------------------
assert_eq "unknown" "$(classify 1 '{}')" \
    "unknown: exit 1 with no subtype"
assert_eq "unknown" "$(classify 1 'not valid json at all')" \
    "unknown: JSON parse failure"

# 合計 12 ケース（AC-16 の「6 分類 × 2 ケース」を満たす）

if ! print_summary; then
    exit 1
fi
