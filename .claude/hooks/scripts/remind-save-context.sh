#!/bin/bash
# セッション終了時のコンテキスト保存リマインド
#
# Stop イベントで実行され、コンテキストの保存を促すメッセージを出力する。
# ブロックはしない（終了フローを阻害しない）。

set -euo pipefail

TODAY=$(date +%Y-%m-%d)
CONVERSATIONS_DIR="raw/conversations"

# 今日のコンテキストファイルが存在するか確認
TODAY_FILES=$(find "$CONVERSATIONS_DIR" -name "${TODAY}_*" -type f 2>/dev/null || true)

if [ -z "$TODAY_FILES" ]; then
    echo ""
    echo "=================================================="
    echo "  コンテキスト保存リマインド"
    echo "=================================================="
    echo ""
    echo "本日のセッションコンテキストが保存されていません。"
    echo ""
    echo "次回セッションのために、以下を記録することを推奨します："
    echo "  - 実施内容・決定事項・未解決事項"
    echo ""
    echo "保存先: ${CONVERSATIONS_DIR}/${TODAY}_[topic].md"
    echo ""
    echo "=================================================="
    echo ""
fi

exit 0
