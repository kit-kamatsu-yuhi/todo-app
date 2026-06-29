---
name: start-issue
description: |
  Issue 実装プロセス。計画→実装→PR作成の3フェーズで進行し、受入基準の RED/GREEN 判定で品質を担保する。
  TRIGGER when: Issue URL + 「進めろ」「やって」「対応して」「実装して」など実装指示を受けたとき。
  DO NOT TRIGGER when: Issue の作成依頼（→ issue スキル）、Issue の調査・質問のみの場合。
user_invocable: true
command: /start-issue
argument-hint: "[Issue URL or Issue番号]"
---

# Issue 実装プロセス

Issue の実装を計画から PR 作成まで管理するスキル。計画策定 → 実装/テスト/レビュー → PR 作成の3フェーズで進行する。

## 前提条件

- 対象 Issue が GitHub に存在すること
- worktree が作成済みであること（`.claude/rules/worktree.md` 参照）

## Phase A: Research + Plan（必須成果物あり）

1. Issue の要件を読み取る（Issue 番号のみ指定された場合は `gh issue view` で本文取得）
2. worktree の作成を確認（未作成なら作成を促す）
3. `/plan-issue` を **必ず** Skill ツールで呼び出して実装計画を策定する
4. **必須成果物**（生成されるまで Phase B に進まない）:
   - `raw/issues/YYYY-MM-DD_<issue番号>/plan.md` — 実装計画
   - `raw/issues/YYYY-MM-DD_<issue番号>/todos.md` — タスクリスト
5. **Claude が plan mode で動作した場合**: その plan 出力を `plan.md` として保存すること
6. ユーザーとディスカッションし、計画を確定する

### Phase A 完了時のコンテキスト圧迫防止

plan.md / todos.md 生成後、会話には**サマリー（1-2行）のみ**を出力し、詳細はファイルに書く。
会話に plan.md の全文を貼り付けないこと。コンテキストが膨れると Phase B の Agent 起動指示が埋没する。

```
✅ plan.md を生成しました: raw/issues/YYYY-MM-DD_XX/plan.md
✅ todos.md を生成しました: raw/issues/YYYY-MM-DD_XX/todos.md

→ Phase B: 実装に進みます（/codex-team all 経由で実装/テスト/レビュー）
```

## Phase B: 実装/テスト/レビュー

> ⛔ **ユーザー承認なしに Phase B に進んではならない**。plan.md + todos.md をユーザーに提示し、「進めていい」「OK」等の明示的な承認を得てから Phase B を開始する。

ユーザー承認後、**Skill ツールで `/codex-team all` を呼び出す**。

`/codex-team` が以下を一括管理する:
- codex-implement + codex-test を Agent ツールで並列起動して実装・テスト
- codex-review + review-agent を Agent ツールで並列起動してレビュー
- acceptance-criteria-agent で受入基準の RED/GREEN 判定
- 受入基準が全 GREEN になるまで最大5回ループ

⚠️ フォールバック: Agent ツール起動失敗時のみ Claude 単体で代替する。

### レビュー対応フロー（PR レビュー指摘への対応）

PR レビューで指摘を受けた場合は `/address-pr-review` → `/codex-team review` で対応する。

## Phase C: PR 作成（必須・スキップ不可）

1. 変更をコミットする（Conventional Commits 準拠）
2. **`/create-pr` を Skill ツールで必ず実行する**（スキップ不可・`gh pr create` の直接実行は禁止）
   - `/create-pr` は内部で `/walkthrough`（changes.md 生成）→ PR 作成を一括実行する
   - PR 作成前に以下の3ファイルが存在することを確認する:
     - `plan.md` — 実装計画（Phase A で生成済み）
     - `todos.md` — タスクリスト（Phase A で生成済み）
     - `changes.md` — `/create-pr` 内部の `/walkthrough` で自動生成
   - 3ファイルが揃っていない場合は PR 作成に進まない
   - 受入基準の充足状況を PR 本文に含める
   - 手動テストチェックリストを PR 本文に含める

## 注意事項

- 各フェーズの開始前にユーザーに確認を取る
- PR サイズは 500行以下を目標とする（超過時は分割を提案する）
- TDD を適用しないケースは `tdd` スキルの適用基準を参照する
- **既存プロジェクトへの導入時**: 既存のディレクトリ構成・テストフレームワーク・CI/CD・リンター等のツールチェーンを優先する。本プロセスが推奨するツールや構成と異なる場合でも、既存プロジェクトの慣習に合わせる
