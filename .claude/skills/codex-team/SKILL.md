---
name: codex-team
description: |
  codex sub-agent チームの一括起動。各モード内で Agent ツールを並列起動する（implement = 実装+テスト並列 / review = レビュー並列 / all = implement → review の順次）。
  TRIGGER when: `/start-issue` Phase B から呼ばれたとき、または直接 `/codex-team` を実行されたとき。
  DO NOT TRIGGER when: 計画策定のみ（→ /plan-issue）、PR 作成のみ（→ /create-pr）。
user_invocable: true
command: /codex-team
argument-hint: "[implement | review | all]"
---

# Codex Team — Sub-Agent 一括起動

codex sub-agent チームを起動し、実装・テスト・レビューを Agent ツールで実行する。

## モード

### `implement` モード

codex-implement + codex-test を Agent ツールで並列起動し、実装とテストを実行する。
完了後、acceptance-criteria-agent で受入基準の RED/GREEN 判定を行う。

### `review` モード

codex-review + review-agent を Agent ツールで並列起動し、レビューを実行する。
- review-agent は `wiki/pages/reviews/` および `raw/` の過去レビュー内容をコンテキストとして参照する
- セキュリティ基準は plan.md の基準および security スキルの知識を参照する

### `all` モード

implement → review の順で実行する。

1. **implement**: codex-implement + codex-test を Agent ツールで並列起動
2. **受入基準判定**: acceptance-criteria-agent で RED/GREEN 判定
3. **review**: codex-review + review-agent を Agent ツールで並列起動
4. **リファクタリング**: レビュー結果を踏まえ、テスト全グリーンを維持しながら改善

## 受入基準の種別と RED/GREEN 判定方法

| 種別 | テストコード作成 | RED/GREEN 判定方法 |
|------|:---:|---|
| 自動テスト（Unit/Integration） | ○ | テストコードの実行結果で判定 |
| E2E テスト | ○ | テストコードの実行結果で判定 |
| セキュリティ基準 | × | ソースコードと基準を照合して判定 |
| 手動テスト | × | ユーザーに確認を求めて判定 |
| その他 Issue 固有の基準 | × | ソースコードと基準を照合、またはユーザーに確認して判定 |

## ループ制御

受入基準が全 GREEN になるまで最大5回ループする。

### ループの終了条件

- acceptance-criteria-agent で全受入基準が GREEN になっている
- review-agent の指摘がすべて解消されている
- ユーザーが実装完了を承認する

### ループの制限

- 最大5回を目安とし、収束しない場合はユーザーに相談する

## フォールバック

Agent ツール起動失敗時のみ Claude 単体で代替する。その場合は PR 本文に `⚠️ フォールバック: <agent名> 起動失敗` と記録する。

## レビュー対応フロー（PR レビュー指摘への対応）

PR レビューで指摘を受けた場合も、codex agent teams で対応する。
レビュー対応完了後、レビュー指摘とその対応内容を汎化して `wiki/pages/reviews/` に保存する（`/address-pr-review` スキルの「レビュー知見の蓄積」セクション参照）。

### 役割分担（必須）

| 役割 | 担当 | 理由 |
|------|------|------|
| 指揮官（オーケストレーション） | Claude | gh pr コメント・push・PR 操作は Claude のみ実行可能 |
| 実装修正 | codex-implement | Agent ツールで起動 |
| レビュー確認 | codex-review + review-agent | Agent ツールで並列起動 |
| テスト修正・追加 | codex-test | Agent ツールで起動 |
| 受入基準再判定 | acceptance-criteria-agent | Agent ツールで起動 |

### フロー

1. Claude（指揮官）が `gh pr view` でレビューコメントを取得する
2. Claude がレビュー指摘を分析し、修正方針を決定する
3. codex-implement / codex-test を Agent ツールで起動し、修正を実行する
4. codex-review + review-agent で修正結果をレビューする
   - review-agent は `wiki/pages/reviews/` および `raw/` の過去レビュー内容も参照する
5. acceptance-criteria-agent で受入基準の再判定を行う
6. Claude（指揮官）が修正をコミット・push し、PR コメントで対応内容を報告する
7. レビュー指摘とその対応内容を汎化して `wiki/pages/reviews/` に保存する

※ codex agent は gh コマンドによる PR 操作・push ができないため、ステップ 1, 2, 6, 7 は必ず Claude（指揮官）が実行すること。
