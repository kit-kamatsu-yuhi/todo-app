#!/usr/bin/env bash
# test-no-permission-mode-in-agents.sh — AGENT.md に permissionMode / defaultMode が無いこと（AC-14）
#
# 背景（plan.md 設計決定 1）:
#   codex-* サブエージェントはローカルからも呼ばれる共有リソース。
#   frontmatter で permissionMode: bypassPermissions を宣言すると
#   ローカルの permissions.deny ガードが素通しになる。
#   よって exoloop/.claude/agents/ および .claude/agents/ 配下の
#   AGENT.md には permissionMode / defaultMode フィールドを書かない。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

find_repo_root() {
    local cur="$1"
    while [ "$cur" != "/" ] && [ -n "$cur" ]; do
        if [ -d "${cur}/exoloop" ] && { [ -d "${cur}/.devcontainer" ] || [ -f "${cur}/CLAUDE.md" ]; }; then
            printf '%s\n' "$cur"
            return 0
        fi
        cur=$(dirname "$cur")
    done
    return 1
}
REPO_ROOT=$(find_repo_root "$SCRIPT_DIR")
if [ -z "$REPO_ROOT" ]; then
    echo "  ! FAIL: repo root not found from $SCRIPT_DIR"
    exit 1
fi

SCAN_ROOTS=(
    "${REPO_ROOT}/exoloop/.claude/agents"
    "${REPO_ROOT}/.claude/agents"
)

echo "=== no permissionMode/defaultMode in AGENT.md (AC-14) ==="
echo "  repo root: ${REPO_ROOT}"

total_hits=0
for root in "${SCAN_ROOTS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r -d '' f; do
        hits=$(awk '
            BEGIN { in_fm=0; fm_count=0 }
            /^---[[:space:]]*$/ {
                fm_count++
                if (fm_count==1) { in_fm=1; next }
                if (fm_count==2) { in_fm=0; exit }
            }
            in_fm { print }
        ' "$f" | grep -cE '^[[:space:]]*(permissionMode|defaultMode)[[:space:]]*:' || true)
        if [ "$hits" -gt 0 ]; then
            echo "  ! HIT: $f (${hits} occurrence(s))"
            total_hits=$((total_hits + hits))
        fi
    done < <(find "$root" -type f -name 'AGENT.md' -print0)
done

assert_eq "0" "$total_hits" "permissionMode / defaultMode の出現数が 0 (両 location 合計)"

if ! print_summary; then
    exit 1
fi
