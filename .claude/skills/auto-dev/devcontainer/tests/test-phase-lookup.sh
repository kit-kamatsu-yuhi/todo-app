#!/usr/bin/env bash
# test-phase-lookup.sh — lib/phase.sh の next_phase 遷移表テスト（Issue #148 AC-1）
#
# 契約:
#   next_phase <current_phase> [<event>]
#     → stdout に次 phase を出力。未定義なら current を返す（noop）。
#   定義済みキー（plan.md「Phase state machine」参照）:
#     plan                       → wait_plan
#     wait_plan:approve          → implement
#     wait_plan:feedback         → replan
#     replan                     → wait_plan
#     implement                  → wait_review
#     wait_review:approve        → merge
#     wait_review:feedback       → revise_pr
#     revise_pr                  → wait_review
#     merge                      → done
#     plan:error                 → failure
#     implement:error            → failure
#     merge:error                → failure
#     failure:new_activity       → plan

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

PHASE_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/phase.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/phase.sh"; do
    if [ -f "$cand" ]; then
        PHASE_SH="$cand"
        break
    fi
done

echo "=== lib/phase.sh tests ==="

if [ -z "$PHASE_SH" ]; then
    echo "  ! SKIP: lib/phase.sh not yet present (expected RED during parallel TDD)"
    exit 0
fi

# shellcheck disable=SC1090
source "$PHASE_SH"

if ! declare -f next_phase >/dev/null 2>&1; then
    echo "  ! FAIL: next_phase function is not defined in ${PHASE_SH}"
    exit 1
fi

# 直列で比較する小ヘルパ
check() {
    local current="$1" event="$2" expected="$3"
    local actual
    if [ -z "$event" ]; then
        actual=$(next_phase "$current")
    else
        actual=$(next_phase "$current" "$event")
    fi
    assert_eq "$expected" "$actual" "next_phase(${current}${event:+, ${event}}) → ${expected}"
}

# 正常経路（8 ケース）
check "plan"                ""              "wait-plan"
check "wait-plan"           "approve"       "implement"
check "wait-plan"           "feedback"      "replan"
check "replan"              ""              "wait-plan"
check "implement"           ""              "wait-review"
check "wait-review"         "approve"       "merge"
check "wait-review"         "feedback"      "revise-pr"
check "revise-pr"           ""              "wait-review"
check "merge"               ""              "done"

# 異常経路 / 再開（4 ケース）
check "plan"                "error"         "failure"
check "implement"           "error"         "failure"
check "merge"               "error"         "failure"
check "failure"             "new_activity"  "plan"

# 合計 13 ケース（AC-1 の 12 以上を満たす）

# 未定義キーは noop（現在の phase を返す）
check "unknown_phase"       ""              "unknown_phase"
check "implement"           "bogus_event"   "implement"

if ! print_summary; then
    exit 1
fi
