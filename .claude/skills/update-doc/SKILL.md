---
name: update-doc
description: ドキュメント更新・コンテキスト統合。wiki/pages の更新、raw/ への原本投入、log.md への履歴記録を行う。push前に実行を推奨。
---

# ドキュメント更新・コンテキスト統合

`wiki/pages/` への蒸留と、`raw/` のコンテキスト投入・整理を行う。詳細な構造・判断基準は `wiki/SCHEMA.md` を参照。

## 1. 変更差分の分析

- デフォルトブランチを検出する（`origin/main` が存在すれば `main`、なければ `master`）
- `git diff --name-only origin/<デフォルトブランチ>...HEAD` で変更ファイルを取得する
- 変更内容を分類する（新機能、バグ修正、リファクタリング等）

## 2. `raw/` コンテキストの収集・作成

- `raw/issues/` から該当 Issue のコンテキストを確認する
- `raw/conversations/` から関連するセッションログを確認する
- 複数ブランチの変更がある場合、それぞれの差分を確認する

### `raw/` にコンテキストが存在しない場合

変更差分に対応する `raw/` の記録が存在しない場合、**`wiki/` への蒸留には進まず**、まず `raw/` に記録を作成する:

- 関連 Issue がある場合: `raw/issues/YYYY-MM-DD_<issue番号>/` にディレクトリと概要 md を作成する
- セッション中の作業記録がある場合: `raw/conversations/YYYY-MM-DD_<topic>.md` に記録する
- いずれも情報が不足している場合: ブランチ全体の履歴を活用して `raw/` を作成する:
  1. `git log --oneline --no-merges --first-parent origin/<デフォルトブランチ>..HEAD` でブランチの全コミット履歴を取得し、作業の流れ・意図の変遷を把握する（マージコミットは除外）
  2. これらを元に `raw/conversations/YYYY-MM-DD_<topic>.md` を作成する（実施内容・決定事項・現在の状態・未解決事項）
  3. 関連 Issue がある場合は `raw/issues/YYYY-MM-DD_<issue番号>/` にも作成する
  4. コミット履歴も不十分な場合は、変更差分から読み取れる内容で最低限の `raw/` ファイルを作成する

**原則: 新しい情報は必ず `raw/` を経由して入る。`raw/` を飛ばして `wiki/` に直接書かない。**

## 3. 重複検出・矛盾解消

- 同一トピックに関する複数の記録を特定する
- 矛盾する情報がないか確認する
- 矛盾がある場合、新しい日付の情報を優先する

## 4. `wiki/pages/` への蒸留・更新

**前提条件**: `raw/` に蒸留元となるコンテキストが存在すること。`raw/` が空または不十分な場合はこのステップをスキップし、手順 2 で作成した `raw/` の内容をユーザーに報告して終了する。

`doc-management` rule および `wiki/SCHEMA.md` の判断基準（Create / Update / Split / Synthesis）に従い、`raw/` の情報を `wiki/pages/` に統合する:

| 知見の種類 | 更新先 |
|-----------|--------|
| UX知見、プロダクトの体験ごとのコンテキスト | `wiki/pages/user-experiences/` |
| 構造変更、新コンポーネント、依存関係の変化 | `wiki/pages/architecture/` |
| セキュリティ知見 | `wiki/pages/security/` |
| インフラ知見 | `wiki/pages/infrastructure/` |
| 再利用可能なパターン | `wiki/pages/templates/` |
| レビュー知見（頻出パターン） | `wiki/pages/reviews/` |
| 概念・用語・横断統合 | `wiki/pages/concepts/` |
| プロジェクト固有の実体（ツール・人・組織） | `wiki/pages/entities/` |

- 各ページの YAML frontmatter（`title` / `genre` / `summary` / `updated` 等）を更新する
- 該当ジャンルの `wiki/pages/<genre>/index.md` と `log.md` を必ず更新する

## 5. レビュー知見の蒸留

`raw/issues/*/reviews.md` からレビュー対応記録を収集し、頻出パターンを `wiki/pages/reviews/` に蒸留する。

### 手順

1. 全ての `raw/issues/*/reviews.md` を走査する
2. レビュー指摘を分類する:
   - セキュリティ（ガード不足、未検証入力等）
   - エラーハンドリング（未インストール時の挙動、フォールバック不足等）
   - パフォーマンス（N+1、不要な再レンダリング等)
   - 設計（責務分離、抽象化レベル等）
   - その他
3. 同一パターンが **2回以上** 出現している場合、`wiki/pages/reviews/` に蒸留対象とする
4. `wiki/pages/reviews/<パターン名>.md` に以下を記録する:

| フィールド | 内容 |
|-----------|------|
| パターン名 | 指摘の要約（例: 「外部CLI未インストール時のガード」） |
| カテゴリ | セキュリティ / エラーハンドリング / パフォーマンス / 設計 / その他 |
| 発生回数 | `raw/` での出現数 |
| 典型的な指摘 | レビューコメントの代表例 |
| 推奨対応 | このパターンへの標準的な対処方法 |
| 関連事例 | 該当する `raw/` レビュー記録へのパス |
| updated | YYYY-MM-DD |

5. 既に `wiki/pages/reviews/` にパターンが存在する場合は、発生回数・関連事例・updated を更新する。`wiki/pages/reviews/index.md` と `log.md` も合わせて更新する

## 6. 古い `raw/` ファイルの扱い

- `raw/` は不変記録。古くなっても削除しない（`check-raw-freshness.sh` で警告表示のみ）
- 陳腐化した `wiki/` ページは `Split` または削除を検討し、対応ジャンルの `log.md` に履歴を残す

## 7. サマリー出力

- `wiki/pages/` の更新箇所の一覧
- 蒸留した知見の一覧
- レビュー知見として蒸留したパターンの一覧
- `wiki/pages/<genre>/log.md` への記録結果
