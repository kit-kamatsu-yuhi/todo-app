---
name: context-load
description: セッション開始時のプロジェクトコンテキスト読み込み。最近の変更、未解決 Issue、wiki / raw を辿って現状を把握する。
---

# プロジェクトコンテキスト読み込み

セッション開始時にプロジェクトの現状を把握する。LLM wiki 方式（`wiki/SCHEMA.md` 参照）の階層を順に辿る。

## 手順

1. **CLAUDE.md の読み込み**
   - プロジェクト概要、技術スタック、構成を確認する

2. **最近の変更を確認**
   - `git log --oneline -20` で直近のコミット履歴を確認する
   - `git status` で未コミットの変更を確認する
   - `git branch -a` でブランチ状況を確認する

3. **未解決 Issue の確認**
   - `gh issue list --state open` で未解決 Issue を一覧する
   - 優先度の高い Issue を特定する

4. **wiki ナビゲーション**
   - `wiki/SCHEMA.md`（構造 + 判断基準）→ `wiki/index.md`（ジャンル一覧）→ 関連ジャンルの `wiki/pages/<genre>/index.md` の順で辿る
   - 必要なページのみ Read する。本文を一括ロードしない

5. **raw 直近コンテキストの確認**
   - `raw/conversations/` の最新ファイルから直近の作業ログを把握する
   - `raw/issues/<YYYY-MM-DD>_<番号>/` の plan.md / changes.md で進行中 Issue の文脈を取得する

6. **サマリー出力**
   - プロジェクトの現状サマリーを出力する
   - 推奨される次のアクションを提案する
