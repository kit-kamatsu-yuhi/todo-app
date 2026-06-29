## exoloop

### 実行フロー（必須・最優先）

GitHub Issue URL（`https://github.com/.../issues/\d+`）を受け取って開発を開始する場合、以下のフローに**必ず**従うこと。直接コードを書き始めてはならない。

1. `/start-issue` コマンドを Skill ツールで実行する
2. Phase A: `/plan-issue` で計画策定 → `plan.md` + `todos.md` → ユーザー承認
3. Phase B: `/codex-team all` で実装/テスト/レビュー
4. Phase C: `/create-pr` で PR 作成（`plan.md`, `todos.md`, `changes.md` の 3 ファイル必須）

**禁止**: Issue を受け取って `/start-issue` を経由せずにコードを書き始めること。

### Sub-Agents 起動ガイド（必須）

| タイミング | エージェント | 起動方法 |
|-----------|------------|---------|
| 設計 | codex-design | Agent ツールで起動 |
| テスト | codex-test | Agent ツールで起動 |
| 実装 | codex-implement | Agent ツールで起動 |
| レビュー | codex-review, review-agent | Agent ツールで並列起動 |
| 受入基準判定 | acceptance-criteria-agent | Agent ツールで起動 |
| レビュー対応 | codex-implement, codex-test, codex-review, review-agent | Claude（指揮官）がオーケストレーション |

※ review-agent は `wiki/pages/reviews/`, `raw/` の過去レビュー内容を参照する
※ Codex CLI 未インストール / 未ログイン時は Claude 単体で代替する（codex-* エージェントのフォールバック。`codex exec` 失敗時も同様）

### 参照先

| 詳細 | パス |
|------|------|
| 実装フロー・エージェント起動 | `.claude/rules/implement-workflow.md` |
| 言語別ルール | `.claude/rules/languages/` |
| スキル定義 | `.claude/skills/` |
| エージェント定義 | `.claude/agents/` |
| コミット規約 | `.claude/rules/commit-message.md` |
| ブランチ戦略 | `.claude/rules/git-branch.md` |
| worktree 運用 | `.claude/rules/worktree.md` |
| ドキュメント管理 | `.claude/rules/doc-management.md` |
| PR レビュー基準 | `.claude/rules/pr-review.md` |
| 日本語執筆ルール | `.claude/rules/natural-japanese.md` |
| セキュリティ設定 | `/security-settings` スキル |

### Hooks

本 exoloop に含まれる hooks は二段構えで配布される（PR #305 install test で APM v0.11.0 が script 本体を consumer の `.claude/hooks/scripts/` に deploy しないことが判明したため）:

1. **settings.json への merge**: `apm install` 時に APM v0.11+ primitive (`.apm/hooks/claude-hooks.json`) が consumer の `.claude/settings.json` の hooks フィールドに自動 merge する。command path は `.claude/hooks/scripts/<name>.sh` 形式
2. **script 本体のコピー**: setup-exoloop が `apm_modules/Clickan/exoloop/.claude/hooks/scripts/*.sh` を consumer の `.claude/hooks/scripts/` にコピー（Step 3b）

### install 後の自動 setup（agent 行動規約）

`apm install Clickan/exoloop ...` を実行したら、続けて同じセッションで Skill ツールから `/setup-exoloop` を呼ぶこと。これは `apm.yml` の `hooks.post_install` には書かない（APM CLI が現時点で auto-exec しないため）。agent 側で install → setup の chain を保証する。

`/setup-exoloop` は `settings.json` / `CLAUDE.md` / `AGENTS.md` の merge と `apm_modules/` から `.claude/agents/`, `.claude/rules/` の補填を行う。hooks は APM v0.11+ から primitive 配布されるため本 skill では扱わない（Issue #222）。
