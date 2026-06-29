# 実装ワークフロー

## 実行フロー（必須・最優先）

Issue URL または Issue 番号を受け取り、「issueを始めろ」のような指示を受けたら、**他のすべてに優先して**以下に従う。直接コードを書き始めてはならない。

1. **Skill ツールで `/start-issue` を呼び出す**
2. Phase A: `/plan-issue` で計画策定 → plan.md + todos.md → ユーザー承認
3. Phase B: `/codex-team all` で実装/テスト/レビュー
4. Phase C: `/create-pr` で PR 作成（plan.md, todos.md, changes.md の3ファイル必須）

## 禁止事項

- Issue URL を受け取って `/start-issue` を経由せずに実装を開始すること
- `/create-pr` を使わずに `gh pr create` 等で直接 PR を作成すること

## Sub-Agents 起動タイミング

| タイミング | エージェント | 方法 |
|-----------|------------|------|
| 計画策定 | `/plan-issue` | Skill ツール |
| 実装+テスト | `/codex-team implement` | Skill ツール → codex-implement + codex-test を Agent ツールで並列起動 |
| レビュー | `/codex-team review` | Skill ツール → codex-review + review-agent を Agent ツールで並列起動 |
| 実装+テスト+レビュー一括 | `/codex-team all` | Skill ツール → implement → review の順で実行 |
| 受入基準 | acceptance-criteria-agent | `/codex-team` 内で Agent ツール起動 |
| レビュー対応 | `/address-pr-review` → `/codex-team review` | Skill ツール |
| PR 作成 | `/create-pr` | Skill ツール |

※ review-agent は `wiki/pages/reviews/`, `raw/` の過去レビュー内容を参照（レビュー知見の蓄積は `/address-pr-review` が担当）
