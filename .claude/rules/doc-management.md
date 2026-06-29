# ドキュメント管理（LLM wiki 方式）

本リポジトリは LLM wiki 方式を採用する。構造・判断基準の詳細は [`wiki/SCHEMA.md`](../../wiki/SCHEMA.md) を参照。本ファイルは運用ハイライトのみ。

## 2 層構造

| 層 | パス | 書き手 | 目的 |
|---|---|---|---|
| raw | `raw/` | 人間（または `/update-doc` が投入） | 事実の不変記録 |
| wiki | `wiki/` | LLM | 意味の解釈・蒸留・横断統合 |

## セッション開始時のフロー

1. `wiki/SCHEMA.md` を読む（構造 + 判断基準）
2. `wiki/index.md`（ジャンル一覧）で関連ジャンル特定
3. `wiki/pages/<genre>/index.md`（ジャンル内カタログ）で個別ページ特定
4. 該当ページのみ読み込み

## 更新ルール（要点）

- ソースコードに影響する知見変化 → 対応ジャンルの `wiki/pages/<genre>/` を更新
- 対話・Issue・外部記事などの原本 → `raw/` に追記（LLM は書き換え禁止）
- Ingest 時は Create / Update / Split / Synthesis の判断基準に従う（SCHEMA.md 参照）
- `wiki/pages/<genre>/index.md` と `log.md` を必ず更新する

## 作業コンテキストの保存

作業の区切りごとに `raw/conversations/YYYY-MM-DD_[topic].md` を追加する。

### 保存タイミング

- セッション終了時
- 大きな作業単位の完了時
- ユーザーから指示されたとき

### 保存内容テンプレート

```markdown
# [作業タイトル]

- date: YYYY-MM-DD
- topic: 作業の概要

## 実施内容
## 決定事項
## 現在のプロジェクト状態
## 未解決事項
```

保存後、関連する wiki ページへの蒸留を検討する。

## push 前の確認

- `git push` 前に wiki の更新漏れがないか確認する
- ソースコード変更がある場合は `/update-doc` の実行を検討する
- pre-push hook が wiki 更新リマインドを表示する

## アーカイブ方針

旧 `docs/tier-3/archives/` に相当する長期保管領域は **持たない**。陳腐化した wiki ページは `log.md` に記録しつつ削除または `Split` による情報整理を行う。raw/ は不変なので削除しない。
