#!/bin/sh
# check-secrets.sh
# PreToolUse hook: Edit|Write でハードコードされたシークレットを検出する
#
# POSIX sh 互換 — bash/zsh どちらの環境でも動作する
# shebang (#!/bin/sh) がインタプリタを決定するため、ユーザーのログインシェルに依存しない
#
# Claude Code は stdin に JSON を渡す:
#   {"tool_name": "Write", "tool_input": {"file_path": "...", "content": "..."}}

set -eu

input=$(cat)

# tool_input からファイルパスとコンテンツを取得
file_path=$(printf '%s' "$input" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || echo "")

content=$(printf '%s' "$input" | python3 -c "
import sys, json
data = json.load(sys.stdin)
ti = data.get('tool_input', {})
print(ti.get('content', ti.get('new_string', '')))
" 2>/dev/null || echo "")

if [ -z "$content" ]; then
  exit 0
fi

# シークレットパターンをチェック（POSIX ERE）
check_pattern() {
  printf '%s' "$content" | grep -qEi -e "$1"
}

found=0

# AWS Access Key
if check_pattern 'AKIA[0-9A-Z]{16}'; then
  found=1
  echo "  - AWS Access Key ID の可能性"
fi

# Private keys
if check_pattern '-----BEGIN.*(PRIVATE|RSA).*KEY-----'; then
  found=1
  echo "  - 秘密鍵の可能性"
fi

# GitHub tokens
if check_pattern 'gh[pousr]_[A-Za-z0-9_]{36,}'; then
  found=1
  echo "  - GitHub トークンの可能性"
fi

# Slack tokens
if check_pattern 'xox[bpoas]-[0-9a-zA-Z-]+'; then
  found=1
  echo "  - Slack トークンの可能性"
fi

# Generic API key/secret patterns
if check_pattern '(api[_-]?key|api[_-]?secret|secret[_-]?key).*[:=].*[a-zA-Z0-9_-]{20,}'; then
  found=1
  echo "  - API キー/シークレットのハードコードの可能性"
fi

# Generic password patterns (文字列リテラルとして直接代入されている場合のみ検出)
# 関数呼び出しの結果への代入（= await / = get / = hash 等）は除外する
if check_pattern '(password|passwd|pwd)[[:space:]]*=[[:space:]]*(.[^)]{7,}|.[[:alnum:]_.-]{8,})'; then
  found=1
  echo "  - パスワードのハードコードの可能性"
fi

if [ "$found" -eq 1 ]; then
  echo ""
  echo "WARNING: シークレットがハードコードされている可能性があります。"
  echo "ファイル: $file_path"
  echo "シークレットは環境変数またはシークレットマネージャーで管理してください。"
  exit 2
fi

exit 0
