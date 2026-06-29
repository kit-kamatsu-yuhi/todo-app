#!/bin/sh
# plan-gate.sh
# PreToolUse hook: Skill matcher
# /create-pr 実行時に plan.md + todos.md の存在を確認する
# なければ exit 2 でブロック

set -eu

input=$(cat)

# Skill ツールの引数からスキル名を取得（jq でパース）
skill_name=$(printf '%s' "$input" | jq -r '.tool_input.skill // ""' 2>/dev/null || echo "")

# /create-pr 以外はスキップ
case "$skill_name" in
  create-pr|/create-pr) ;;
  *) exit 0 ;;
esac

# git リポジトリのルートを取得
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
ISSUES_DIR="$REPO_ROOT/raw/issues"

# issues ディレクトリが存在しなければスキップ
if [ ! -d "$ISSUES_DIR" ]; then
  exit 0
fi

# ブランチ名から Issue 番号を抽出（feature/<issue番号>-* パターンのみ）
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
ISSUE_NUM=$(printf '%s' "$BRANCH" | sed -n 's|^feature/\([0-9]*\)-.*|\1|p')

# feature/<issue番号>-* パターンにマッチしなければスキップ
# フォールバックで別 Issue のディレクトリを拾うバグを防ぐ
if [ -z "$ISSUE_NUM" ]; then
  exit 0
fi

# Issue 番号で issue ディレクトリを探す
# 日付プレフィックスの逆順ソートで最新ディレクトリを採用する
issue_dir=""

for dir in "$ISSUES_DIR"/*_"$ISSUE_NUM"/; do
  if [ -d "$dir" ]; then
    issue_dir=$(printf '%s' "$dir" | sed 's|/$||')
    # 上書きし続け、ソート順で最後（最新日付）を残す
  fi
done

# ディレクトリが見つからなければスキップ
if [ -z "$issue_dir" ]; then
  exit 0
fi

# plan.md と todos.md の存在チェック
missing_files=""

if [ ! -f "${issue_dir}/plan.md" ]; then
  missing_files="${missing_files}  - plan.md（実装計画）\n"
fi

if [ ! -f "${issue_dir}/todos.md" ]; then
  missing_files="${missing_files}  - todos.md（タスクリスト）\n"
fi

if [ -n "$missing_files" ]; then
  echo "BLOCKED: PR 作成に必要なファイルが見つかりません。"
  echo ""
  echo "ブランチ: $BRANCH (Issue #$ISSUE_NUM)"
  echo "対象ディレクトリ: $issue_dir"
  echo ""
  echo "不足ファイル:"
  printf '%b' "$missing_files"
  echo ""
  echo "/plan-issue で計画を策定してから /create-pr を実行してください。"
  exit 2
fi

exit 0
