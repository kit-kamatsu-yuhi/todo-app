#!/bin/bash
# PostToolUse hook: agent skill / rules ファイルの編集を検知し、
# NVIDIA SkillSpector で静的 scan を回す。risk_score > 50 で exit 2 を返し
# Claude に findings を通知する。
#
# 実行方式の自動選択:
#   1. ターゲットから上方探索して skillspector を依存にもつ pyproject.toml を
#      見つけたら、その uv プロジェクトを使う (高速・キャッシュ済み)
#   2. 見つからなければ uvx で git からエフェメラル実行
#   3. uv / uvx どちらも無ければ silent skip (consumer が後で導入する余地を残す)
#
# 対応エージェント (任意のディレクトリ深さでマッチ):
#   - Claude Code:  .claude/skills/<name>/SKILL.md
#   - Cursor:       .cursor/rules/*.mdc, .cursorrules
#   - Cline:        .clinerules/*
#   - Windsurf:     .windsurfrules, .windsurf/rules/*.md
#   - Continue:     .continue/config.json, .continue/*.prompt
#   - Aider:        CONVENTIONS.md, .aider.conf.yml
#
# skillspector tag は git tag 未発行のため commit SHA で固定。
# upstream リリース後は SKILLSPECTOR_REF を更新する。

set -uo pipefail

SKILLSPECTOR_GIT="git+https://github.com/NVIDIA/skillspector"
SKILLSPECTOR_REF="${SKILLSPECTOR_REF:-1a7bf026a3cf0ecfd957b6c173244d51b3141baf}"

INPUT="$(cat)"
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

case "$TOOL" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE" ]] && exit 0
[[ -f "$FILE" ]] || exit 0

case "$FILE" in
  */.claude/skills/*/SKILL.md) ;;
  */.cursor/rules/*.mdc) ;;
  */.cursorrules) ;;
  */.clinerules/*) ;;
  */.windsurfrules) ;;
  */.windsurf/rules/*) ;;
  */.continue/*.prompt|*/.continue/config.json) ;;
  */CONVENTIONS.md|*/.aider.conf.yml) ;;
  *) exit 0 ;;
esac

# pyproject.toml に skillspector が宣言されているプロジェクトを上方探索
project=""
d="$(dirname "$FILE")"
while [[ "$d" != "/" && -n "$d" ]]; do
  if [[ -f "$d/pyproject.toml" ]] && grep -q "skillspector" "$d/pyproject.toml" 2>/dev/null; then
    project="$d"
    break
  fi
  parent="$(dirname "$d")"
  [[ "$parent" == "$d" ]] && break
  d="$parent"
done

run_scan() {
  if [[ -n "$project" ]] && command -v uv >/dev/null 2>&1; then
    ( cd "$project" && uv run --quiet skillspector scan "$FILE" --no-llm )
  elif command -v uvx >/dev/null 2>&1; then
    uvx --quiet --from "${SKILLSPECTOR_GIT}@${SKILLSPECTOR_REF}" \
        skillspector scan "$FILE" --no-llm
  elif command -v uv >/dev/null 2>&1; then
    uv tool run --quiet --from "${SKILLSPECTOR_GIT}@${SKILLSPECTOR_REF}" \
        skillspector scan "$FILE" --no-llm
  else
    return 0
  fi
}

if ! run_scan >&2; then
  echo "" >&2
  echo "❌ SkillSpector が $FILE で findings を検出した (risk_score > 50)" >&2
  echo "   詳細は上の出力を確認。" >&2
  exit 2
fi

exit 0
