#!/bin/sh
# recommend-create-pr.sh
# PreToolUse hook: Bash matcher
# `gh pr create` の実行を検知し、/create-pr スキルの使用を推奨する
# ブロックはしない（exit 0）。stdout で推奨メッセージを表示する。

set -eu

input=$(cat)

# tool_input.command を取得（jq でパース）
command_str=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

if [ -z "$command_str" ]; then
  exit 0
fi

# クォート内の文字列を除外（誤検知防止）
sanitized_str=$(printf '%s' "$command_str" | sed "s/<<'*[A-Za-z_]*'*.*//; s/'[^']*'/ /g; s/\"[^\"]*\"/ /g")

# gh pr create を検知
if printf '%s' "$sanitized_str" | grep -qE 'gh[[:space:]]+pr[[:space:]]+create'; then
  echo "💡 /create-pr スキルを使うと Linear Walkthrough + Mermaid 付き PR を一括作成できます。"
fi

exit 0
