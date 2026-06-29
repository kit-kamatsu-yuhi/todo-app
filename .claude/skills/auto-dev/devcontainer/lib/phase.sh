#!/bin/bash
# Phase state-machine lookup for auto-dev.
#
# Phases:
#   plan          — プラン未投稿
#   wait-plan     — プラン投稿済み、ユーザー応答待ち
#   replan        — ユーザーフィードバック反映
#   implement     — 承認済み、実装中
#   wait-review   — PR 作成、レビュー待ち
#   revise-pr     — レビューフィードバック反映
#   merge         — 承認済み、マージ実行
#   done          — 完了
#   failure       — エラー終了（new_activity で再開）
#
# Events (optional 2nd arg):
#   approve, feedback, error, new_activity
#
# Returns the next phase via stdout. Unknown transitions return the current
# phase unchanged (stable: the caller continues with the existing state).
#
# 実装メモ: bash 3.2 でも動作するよう case 文ベースのルックアップを採用する
# （associative array は bash 4.2+ のみ）。論理は plan.md の state machine 図に
# 従い、単一関数で全遷移を記述する。

if [ -n "${_AUTO_DEV_PHASE_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AUTO_DEV_PHASE_SOURCED=1

# next_phase <current> [event]
# Looks up the next phase. When no transition exists, prints <current>.
next_phase() {
    local current="${1:-}"
    local event="${2:-}"
    local key="$current"
    if [ -n "$event" ]; then
        key="${current}:${event}"
    fi

    case "$key" in
        plan)                   printf '%s\n' "wait-plan" ;;
        wait-plan:approve)      printf '%s\n' "implement" ;;
        wait-plan:feedback)     printf '%s\n' "replan" ;;
        replan)                 printf '%s\n' "wait-plan" ;;
        implement)              printf '%s\n' "wait-review" ;;
        wait-review:approve)    printf '%s\n' "merge" ;;
        wait-review:feedback)   printf '%s\n' "revise-pr" ;;
        revise-pr)              printf '%s\n' "wait-review" ;;
        merge)                  printf '%s\n' "done" ;;
        plan:error)             printf '%s\n' "failure" ;;
        implement:error)        printf '%s\n' "failure" ;;
        merge:error)            printf '%s\n' "failure" ;;
        replan:error)           printf '%s\n' "failure" ;;
        revise-pr:error)        printf '%s\n' "failure" ;;
        failure:new_activity)   printf '%s\n' "plan" ;;
        *)                      printf '%s\n' "$current" ;;
    esac
}

# is_terminal_phase <phase>
# Returns 0 when the phase is terminal (done / failure).
is_terminal_phase() {
    case "${1:-}" in
        done|failure) return 0 ;;
        *) return 1 ;;
    esac
}

export -f next_phase is_terminal_phase 2>/dev/null || true
