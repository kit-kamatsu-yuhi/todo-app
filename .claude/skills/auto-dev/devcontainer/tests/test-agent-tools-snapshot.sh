#!/usr/bin/env bash
# test-agent-tools-snapshot.sh — 9 agent の tools に Write / Edit 追加を検証（AC-11）
#
# 対象（plan.md 参照、対象外 3 agent を除く 9 agent）:
#   codex-implement / codex-test / codex-design / codex-review
#   test-agent / review-agent / doc-agent / migration-agent / security-agent
#
# 対象外（read-only 維持）:
#   acceptance-criteria-agent / aws-infra-review-agent / gcp-infra-review-agent
#
# 検証:
#   exoloop/.claude/agents/<name>/AGENT.md の frontmatter で tools: に
#   `Write` と `Edit` が両方含まれていること。AGENT.md が両 location（exoloop と
#   リポジトリ自身の .claude/agents/）に存在する場合は両方検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

# repo root を marker で自動検出（primary / mirror の両 location から呼べる）
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

AGENTS=(
    codex-implement
    codex-test
    codex-design
    codex-review
    test-agent
    review-agent
    doc-agent
    migration-agent
    security-agent
)

BASES=(
    "${REPO_ROOT}/exoloop/.claude/agents"
    "${REPO_ROOT}/.claude/agents"
)

echo "=== agent tools snapshot (AC-11) ==="
echo "  repo root: ${REPO_ROOT}"

# frontmatter（最初の ---  から 2 つ目の ---）内で tools: の下の `- <tool>` 行を探す
frontmatter_contains_tool() {
    local file="$1" tool="$2"
    awk '
        BEGIN { in_fm=0; fm_count=0 }
        /^---[[:space:]]*$/ {
            fm_count++
            if (fm_count==1) { in_fm=1; next }
            if (fm_count==2) { in_fm=0; exit }
        }
        in_fm { print }
    ' "$file" | grep -Eq "^[[:space:]]*-[[:space:]]+${tool}[[:space:]]*$"
}

any_found=0
for base in "${BASES[@]}"; do
    if [ ! -d "$base" ]; then
        continue
    fi
    case "$base" in
        */exoloop/*) base_tag="exoloop";;
        *)                base_tag="repo";;
    esac
    for agent in "${AGENTS[@]}"; do
        f="${base}/${agent}/AGENT.md"
        if [ ! -f "$f" ]; then
            continue
        fi
        any_found=1
        assert_true "${agent} (${base_tag}): tools に Write を含む" \
            frontmatter_contains_tool "$f" "Write"
        assert_true "${agent} (${base_tag}): tools に Edit を含む" \
            frontmatter_contains_tool "$f" "Edit"
    done
done

if [ "$any_found" -eq 0 ]; then
    echo "  ! FAIL: 対象 agent の AGENT.md が両 location に見当たらない"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("no AGENT.md found")
fi

if ! print_summary; then
    exit 1
fi
