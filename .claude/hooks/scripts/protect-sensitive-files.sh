#!/bin/sh
# protect-sensitive-files.sh
# PreToolUse hook: Edit|Write で機密ファイルへの変更をブロックする
#
# POSIX sh 互換 — bash/zsh どちらの環境でも動作する
# shebang (#!/bin/sh) がインタプリタを決定するため、ユーザーのログインシェルに依存しない
#
# Claude Code は stdin に JSON を渡す:
#   {"tool_name": "Write", "tool_input": {"file_path": ".env", ...}}

set -eu

input=$(cat)

# tool_input.file_path を取得
file_path=$(printf '%s' "$input" | python3 -c "
import sys, json
data = json.load(sys.stdin)
tool_input = data.get('tool_input', {})
print(tool_input.get('file_path', ''))
" 2>/dev/null || echo "")

if [ -z "$file_path" ]; then
  exit 0
fi

# 保護対象パターンをチェック（POSIX ERE: [[:space:]] を使用、\s は非POSIX）
check_pattern() {
  printf '%s' "$file_path" | grep -qE -e "$1"
}

if check_pattern '\.env$' \
   || check_pattern '\.env\.' \
   || check_pattern '(^|/)secrets\.[^/]+$' \
   || check_pattern '\.pem$' \
   || check_pattern '\.key$' \
   || check_pattern '\.p12$' \
   || check_pattern '\.pfx$' \
   || check_pattern '\.jks$' \
   || check_pattern 'credentials\.json$' \
   || check_pattern 'service[-_]account.*\.json$' \
   || check_pattern 'id_rsa' \
   || check_pattern 'id_ed25519'; then
  echo "BLOCKED: 機密ファイル '$file_path' への変更はブロックされました。"
  echo "このファイルを変更する必要がある場合は、手動で行ってください。"
  exit 2
fi

exit 0
