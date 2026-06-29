#!/usr/bin/env bash
# test-prompt-split-rule.sh — codex-implement / codex-test に分割ルールが書かれている（AC-12）
#
# 検証項目:
#   codex-implement/AGENT.md と codex-test/AGENT.md の両方に、
#   「複合 Bash 連結禁止」と「Write ツール第一選択」を示す記述があること。
#   文言ゆらぎを許容するため正規表現で複数バリエーションをカバーする。

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

BASES=(
    "${REPO_ROOT}/exoloop/.claude/agents"
    "${REPO_ROOT}/.claude/agents"
)

TARGETS=(codex-implement codex-test)

echo "=== prompt split rule (AC-12) ==="
echo "  repo root: ${REPO_ROOT}"

SPLIT_PATTERNS=(
    '複合.*Bash.*連結'
    '連結.*禁止'
    '&&.*連結.*しない'
    'bash -n.*別.*呼'
)

WRITE_PATTERNS=(
    'Write.*ツール.*第一選択'
    'Write.*第一.*選択'
    'heredoc.*最後の手段'
    'Write を優先'
)

contains_any() {
    local file="$1"
    shift
    local pat
    for pat in "$@"; do
        if grep -Eq -- "$pat" "$file"; then
            return 0
        fi
    done
    return 1
}

found_any=0
for base in "${BASES[@]}"; do
    [ -d "$base" ] || continue
    case "$base" in
        */exoloop/*) base_tag="exoloop";;
        *)                base_tag="repo";;
    esac
    for agent in "${TARGETS[@]}"; do
        f="${base}/${agent}/AGENT.md"
        [ -f "$f" ] || continue
        found_any=1

        if contains_any "$f" "${SPLIT_PATTERNS[@]}"; then
            assert_true "${agent} (${base_tag}): 複合 Bash 連結禁止の記述あり" true
        else
            assert_true "${agent} (${base_tag}): 複合 Bash 連結禁止の記述あり" false
        fi

        if contains_any "$f" "${WRITE_PATTERNS[@]}"; then
            assert_true "${agent} (${base_tag}): Write ツール第一選択の記述あり" true
        else
            assert_true "${agent} (${base_tag}): Write ツール第一選択の記述あり" false
        fi
    done
done

if [ "$found_any" -eq 0 ]; then
    echo "  ! FAIL: 対象の AGENT.md が両 location のいずれにも見当たらない"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("no target AGENT.md found")
fi

if ! print_summary; then
    exit 1
fi
