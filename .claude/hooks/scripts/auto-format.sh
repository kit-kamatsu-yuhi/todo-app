#!/bin/bash
# PostToolUse hook: ファイル拡張子に基づく自動フォーマット
# Edit/Write ツール実行後に対象ファイルをフォーマットする

set -euo pipefail

# jq が未インストールなら graceful skip
if ! command -v jq &>/dev/null; then
  cat > /dev/null
  exit 0
fi

# stdin から JSON を読み取る
INPUT=$(cat)

# ツール名を取得
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Edit/Write 以外は skip
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# ファイルパスを取得
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# 拡張子を取得
EXT="${FILE_PATH##*.}"

# 拡張子に応じてフォーマッターを実行
case "$EXT" in
  ts|tsx|js|jsx)
    if command -v biome &>/dev/null; then
      biome format --write "$FILE_PATH" 2>/dev/null || true
    elif command -v oxfmt &>/dev/null; then
      oxfmt "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  py)
    if command -v ruff &>/dev/null; then
      ruff format "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  kt|kts)
    if command -v ktlint &>/dev/null; then
      ktlint -F "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  go)
    if command -v gofmt &>/dev/null; then
      gofmt -w "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  rs)
    if command -v rustfmt &>/dev/null; then
      rustfmt "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  java)
    if command -v google-java-format &>/dev/null; then
      google-java-format -i "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
  swift)
    if command -v swift-format &>/dev/null; then
      swift-format format -i "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
esac
