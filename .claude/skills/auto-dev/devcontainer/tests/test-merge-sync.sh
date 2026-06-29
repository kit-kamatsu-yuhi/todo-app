#!/usr/bin/env bash
# test-merge-sync.sh — process-issue.sh の merge phase 静的検証（Issue #147 回帰検知）
#
# 目的:
#   Issue #147 で process-issue.sh の merge phase に追加した以下 3 コマンドが
#   今後のリファクタで消えないことを保証する。
#     - git fetch origin "$BRANCH"
#     - git checkout "$BRANCH"
#     - git reset --hard "origin/$BRANCH"
#
#   加えて .devcontainer/ 側と exoloop mirror の merge phase ブロックが
#   同一であること（drift なし）を検証する。
#
# 実行方法:
#   bash .devcontainer/auto-dev/tests/test-merge-sync.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

# リポジトリルート解決（tests/ の 3 階層上が worktree ルート）
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

PRIMARY_SH="${REPO_ROOT}/.devcontainer/auto-dev/lib/process-issue.sh"
MIRROR_SH="${REPO_ROOT}/exoloop/.claude/skills/auto-dev/devcontainer/lib/process-issue.sh"

TMP_DIR="$(mktemp -d)"
PRIMARY_BLOCK="${TMP_DIR}/primary.block"
MIRROR_BLOCK="${TMP_DIR}/mirror.block"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "=== process-issue.sh merge phase 静的検証 ==="

# --- 前提: 両ファイルが存在すること ---
assert_true "primary process-issue.sh exists" [ -f "$PRIMARY_SH" ]
assert_true "mirror process-issue.sh exists" [ -f "$MIRROR_SH" ]

# --- merge phase ブロックの抽出 ---
# 4 スペースの `"merge")` から最初の 8 スペース `;;` までを範囲抽出する。
extract_merge_block() {
    local src="$1"
    local dst="$2"
    awk '/^    "merge"\)/,/^        ;;/' "$src" > "$dst"
}

extract_merge_block "$PRIMARY_SH" "$PRIMARY_BLOCK"
extract_merge_block "$MIRROR_SH" "$MIRROR_BLOCK"

assert_true "primary merge block is non-empty" [ -s "$PRIMARY_BLOCK" ]
assert_true "mirror merge block is non-empty" [ -s "$MIRROR_BLOCK" ]

# --- テストケース 1: primary に 3 コマンドが含まれる ---
echo ""
echo "Primary (.devcontainer/auto-dev/lib/process-issue.sh):"

assert_true 'primary contains: git fetch origin "$BRANCH"' \
    grep -Fq 'git fetch origin "$BRANCH"' "$PRIMARY_BLOCK"
assert_true 'primary contains: git checkout "$BRANCH"' \
    grep -Fq 'git checkout "$BRANCH"' "$PRIMARY_BLOCK"
assert_true 'primary contains: git reset --hard "origin/$BRANCH"' \
    grep -Fq 'git reset --hard "origin/$BRANCH"' "$PRIMARY_BLOCK"

# --- テストケース 2: mirror に 3 コマンドが含まれる ---
echo ""
echo "Mirror (exoloop/.claude/skills/auto-dev/devcontainer/lib/process-issue.sh):"

assert_true 'mirror contains: git fetch origin "$BRANCH"' \
    grep -Fq 'git fetch origin "$BRANCH"' "$MIRROR_BLOCK"
assert_true 'mirror contains: git checkout "$BRANCH"' \
    grep -Fq 'git checkout "$BRANCH"' "$MIRROR_BLOCK"
assert_true 'mirror contains: git reset --hard "origin/$BRANCH"' \
    grep -Fq 'git reset --hard "origin/$BRANCH"' "$MIRROR_BLOCK"

# --- テストケース 3: primary と mirror の merge phase ブロックが同一 ---
echo ""
echo "Drift check (primary vs mirror):"

assert_true "primary and mirror merge blocks are identical" \
    diff -q "$PRIMARY_BLOCK" "$MIRROR_BLOCK"

# --- Summary ---
if ! print_summary; then
    exit 1
fi
