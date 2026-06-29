#!/bin/sh
# push-gate.sh
# PreToolUse hook: Bash matcher
# git push 前に wiki/pages 更新と changes.md の存在をチェックする
#
# フェイルセーフ: 警告のみ（exit 0）。hook が壊れても通常動作に戻る。

set -eu

input=$(cat)

# tool_input.command を取得
command_str=$(printf '%s' "$input" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
print(tool_input.get('command', ''))
" 2>/dev/null || echo "")

if [ -z "$command_str" ]; then
  exit 0
fi

# クォート内の文字列を除外（誤検知防止）
sanitized_str=$(printf '%s' "$command_str" | python3 -c "
import sys, re
s = sys.stdin.read()
s = re.sub(r\"<<'?(\w+)'?.*?\\1\", ' ', s, flags=re.DOTALL)
s = re.sub(r\"'[^']*'\", ' ', s)
s = re.sub(r'\"[^\"]*\"', ' ', s)
print(s)
" 2>/dev/null || printf '%s' "$command_str")

# git push 以外はスキップ
if ! printf '%s' "$sanitized_str" | grep -qE 'git[[:space:]]+push'; then
  exit 0
fi

# git リポジトリのルートを取得
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ISSUES_DIR="$REPO_ROOT/raw/issues"

# ブランチ名から Issue 番号を抽出
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
ISSUE_NUM=$(printf '%s' "$BRANCH" | sed -n 's|^feature/\([0-9]*\).*|\1|p')

# feature ブランチ以外はスキップ
if [ -z "$ISSUE_NUM" ]; then
  exit 0
fi

warnings=""

# --- diff base の動的解決 ---
# merge-base を使い、main/master 以外のブランチから切った場合にも対応する
DIFF_BASE=""
# 1. @{upstream} の merge-base を試す（tracking branch 設定済みの場合）
DIFF_BASE=$(git merge-base HEAD "@{upstream}" 2>/dev/null || echo "")
# 2. origin/HEAD（リモートのデフォルトブランチ）にフォールバック
if [ -z "$DIFF_BASE" ]; then
  DIFF_BASE=$(git merge-base HEAD "origin/HEAD" 2>/dev/null || echo "")
fi
# 3. origin/main にフォールバック
if [ -z "$DIFF_BASE" ]; then
  DIFF_BASE=$(git merge-base HEAD "origin/main" 2>/dev/null || echo "")
fi

# --- チェック 1: wiki ドキュメント更新 ---
if [ -n "$DIFF_BASE" ]; then
  has_src_changes=$(git diff --name-only "${DIFF_BASE}...HEAD" -- . ':!raw/' ':!wiki/' ':!docs/' 2>/dev/null | head -1)
  has_tier1_changes=$(git diff --name-only "${DIFF_BASE}...HEAD" -- wiki/pages/ 2>/dev/null | head -1)

  if [ -n "$has_src_changes" ] && [ -z "$has_tier1_changes" ]; then
    warnings="${warnings}  - wiki/pages/ の更新がありません（ソースコード変更あり）\n"
    warnings="${warnings}    → /update-doc の実行を検討してください\n"
  fi
fi

# --- チェック 2: changes.md の存在 ---
# 日付プレフィックスの逆順ソートで最新ディレクトリを採用する
issue_dir=""

if [ -d "$ISSUES_DIR" ] && [ -n "$ISSUE_NUM" ]; then
  for dir in "$ISSUES_DIR"/*_"$ISSUE_NUM"/; do
    if [ -d "$dir" ]; then
      issue_dir=$(printf '%s' "$dir" | sed 's|/$||')
      # 上書きし続け、ソート順で最後（最新日付）を残す
    fi
  done
fi

if [ -n "$issue_dir" ] && [ ! -f "${issue_dir}/changes.md" ]; then
  warnings="${warnings}  - ${issue_dir}/changes.md が見つかりません\n"
  warnings="${warnings}    → /create-pr で PR を作成すると自動生成されます\n"
fi

# 警告があれば表示
if [ -n "$warnings" ]; then
  echo ""
  echo "=================================================="
  echo "  push 前チェック（警告）"
  echo "=================================================="
  echo ""
  echo "ブランチ: $BRANCH (Issue #$ISSUE_NUM)"
  echo ""
  echo "以下の点を確認してください:"
  printf '%b' "$warnings"
  echo ""
  echo "意図的であれば無視して構いません。"
  echo ""
  echo "=================================================="
  echo ""
fi

exit 0
