#!/bin/bash
# セッション開始時のコンテキスト自動読み込み
#
# SessionStart イベントで実行される。
# プロジェクトの最近の変更と未解決 Issue を要約して出力する。
# ブロックはしない（セッション開始フローを阻害しない）。

set -euo pipefail

echo ""
echo "=================================================="
echo "  プロジェクトコンテキスト"
echo "=================================================="
echo ""

# 直近のコミット（最大5件）
echo "## 直近のコミット"
git log --oneline -5 2>/dev/null || echo "(git log 取得失敗)"
echo ""

# デフォルトブランチを検出（main → master フォールバック）
if git rev-parse --verify refs/heads/main >/dev/null 2>&1; then
    DEFAULT_BRANCH="main"
elif git rev-parse --verify refs/heads/master >/dev/null 2>&1; then
    DEFAULT_BRANCH="master"
else
    DEFAULT_BRANCH="main"
fi

# 未マージのブランチ
BRANCHES=$(git branch --no-merged "$DEFAULT_BRANCH" 2>/dev/null | head -5 || true)
if [ -n "$BRANCHES" ]; then
    echo "## 未マージブランチ"
    echo "$BRANCHES"
    echo ""
fi

# 最新の raw/conversations（直近3件）
CONVERSATIONS_DIR="raw/conversations"
if [ -d "$CONVERSATIONS_DIR" ]; then
    RECENT_CONVERSATIONS=$(ls -t "$CONVERSATIONS_DIR"/*.md 2>/dev/null | head -3 || true)
    if [ -n "$RECENT_CONVERSATIONS" ]; then
        echo "## 直近の対話ログ"
        for f in $RECENT_CONVERSATIONS; do
            echo "  - $(basename "$f")"
        done
        echo ""
    fi
fi

# 最新の raw/issues（直近3件）
ISSUES_DIR="raw/issues"
if [ -d "$ISSUES_DIR" ]; then
    RECENT_ISSUES=$(ls -dt "$ISSUES_DIR"/*/ 2>/dev/null | head -3 || true)
    if [ -n "$RECENT_ISSUES" ]; then
        echo "## 直近の Issue"
        for d in $RECENT_ISSUES; do
            echo "  - $(basename "$d")"
        done
        echo ""
    fi
fi

# Wiki カタログ（ジャンル一覧）
WIKI_INDEX="wiki/index.md"
if [ -f "$WIKI_INDEX" ]; then
    echo "## Wiki カタログ"
    # frontmatter をスキップして本文冒頭のジャンル一覧テーブルを表示（最大 30 行）
    awk '
        BEGIN { fm=0; done_fm=0 }
        NR==1 && /^---$/ { fm=1; next }
        fm==1 && /^---$/ { fm=0; done_fm=1; next }
        fm==1 { next }
        done_fm==1 { print }
    ' "$WIKI_INDEX" | head -30
    echo ""
fi

# Wiki SCHEMA.md 章見出し（H2 のみ）
SCHEMA_FILE="wiki/SCHEMA.md"
if [ -f "$SCHEMA_FILE" ]; then
    echo "## Wiki SCHEMA 章見出し"
    grep -E '^## ' "$SCHEMA_FILE" | sed 's/^## /  - /' || true
    echo ""
fi

# 各ジャンルのページタイトル一覧（frontmatter の title のみ抽出）
WIKI_PAGES_DIR="wiki/pages"
if [ -d "$WIKI_PAGES_DIR" ]; then
    echo "## Wiki ページタイトル"
    for genre_dir in "$WIKI_PAGES_DIR"/*/; do
        [ -d "$genre_dir" ] || continue
        genre=$(basename "$genre_dir")
        printed_genre=0
        for page in "$genre_dir"*.md; do
            [ -f "$page" ] || continue
            base=$(basename "$page")
            case "$base" in
                index.md|log.md) continue ;;
            esac
            title=$(awk '
                BEGIN { fm=0 }
                /^---$/ { fm++; if (fm==2) exit; next }
                fm==1 && /^title:/ {
                    sub(/^title:[[:space:]]*/, "")
                    gsub(/^["'\'']|["'\'']$/, "")
                    print
                    exit
                }
            ' "$page")
            if [ -n "$title" ]; then
                if [ "$printed_genre" -eq 0 ]; then
                    echo "  [$genre]"
                    printed_genre=1
                fi
                echo "    - $base: $title"
            fi
        done
    done
    echo ""
fi

echo "=================================================="
echo "  詳細は /context-load で読み込めます"
echo "=================================================="
echo ""

echo "=================================================="
echo "  Wiki 読み込み手順（エージェント用）"
echo "=================================================="
echo ""
echo "セッション開始時は以下の順で読むこと:"
echo "  1. wiki/SCHEMA.md（構造 + 判断基準）"
echo "  2. wiki/index.md（ジャンル一覧）"
echo "  3. 関連ジャンルの wiki/pages/<genre>/index.md"
echo "=================================================="
echo ""

exit 0
