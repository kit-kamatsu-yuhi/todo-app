#!/usr/bin/env bash
# 権限定期監査: SessionStart 時にセキュリティ設定の概要を表示する
set -euo pipefail

SETTINGS_FILE=".claude/settings.json"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "⚠️ settings.json が見つかりません"
  exit 0
fi

# jq が利用可能か確認
if ! command -v jq &>/dev/null; then
  echo "⚠️ jq が未インストールのため権限監査をスキップ"
  exit 0
fi

echo "=================================================="
echo "  セキュリティ設定監査"
echo "=================================================="

# deny ルール数
DENY_COUNT=$(jq '.permissions.deny | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
echo ""
echo "deny ルール数: $DENY_COUNT"

# deny ルールのカテゴリ別内訳
if [[ "$DENY_COUNT" -gt 0 ]]; then
  BASH_DENY=$(jq '[.permissions.deny[] | select(startswith("Bash("))] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
  READ_DENY=$(jq '[.permissions.deny[] | select(startswith("Read("))] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
  echo "  - Bash コマンド制限: ${BASH_DENY}件"
  echo "  - ファイル読取制限: ${READ_DENY}件"
fi

# PreToolUse hooks 数
PRETOOL_HOOKS=$(jq '[.hooks.PreToolUse[]?.hooks[]?] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
echo "PreToolUse hooks: ${PRETOOL_HOOKS}件"

# セキュリティレベルの簡易判定
echo ""
if [[ "$DENY_COUNT" -ge 40 ]]; then
  echo "セキュリティレベル: 🔒 厳格"
elif [[ "$DENY_COUNT" -ge 15 ]]; then
  echo "セキュリティレベル: 🔐 標準"
else
  echo "セキュリティレベル: 🔓 緩和"
fi

echo "=================================================="
