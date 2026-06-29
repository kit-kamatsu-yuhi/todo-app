---
name: issue
description: 構造化されたGitHub Issueを作成する。最小単位に分割した上で、概要・要件・デザイン・TODO・受け入れ条件・関連Issueの構造で起票する。
argument-hint: "[Issueの概要]"
---

# 構造化 GitHub Issue 作成

$ARGUMENTS を基に構造化された GitHub Issue を作成する。

## 原則: Issue は最小単位に分ける

1 つの Issue で 1 つの機能・1 つの関心事だけを扱う。大きな機能は複数の Issue に分割し、`関連 Issue` で相互リンクする。

## 手順

1. **要件の整理と分割**
   - Issue の目的と背景を明確にする
   - 機能が大きい場合は、最小単位の Issue に分割する
   - 関連する既存 Issue やドキュメントを確認する

2. **Issue の構造化**
   以下のフォーマットで Issue を作成する:

   ```markdown
   ## 概要
   何を実現するか（1-2文）

   ## 要件
   - 実現したい振る舞い
   - 制約条件
   - 非機能要件（パフォーマンス・セキュリティ等）

   ## デザイン（あれば）
   UI モック、アーキテクチャ図、API 設計など
   固まっていなければ省略

   ## TODO
   - [ ] タスク1
   - [ ] タスク2
   - [ ] テストを追加する
   - [ ] ドキュメントを更新する

   ## 受け入れ条件（固まっていれば）
   - [ ] Given/When/Then 形式で書く
   - [ ] テストで検証可能な粒度にする

   ## 関連 Issue
   - Parent: #N
   - Depends on: #M
   - Blocks: #L
   ```

3. **ラベル付け**
   - タイプ: `feat` / `fix` / `chore` / `docs` / `refactor`
   - 優先度: `priority:high` / `priority:medium` / `priority:low`
   - サイズ: `size:S` / `size:M` / `size:L` / `size:XL`

4. **GitHub Issue の作成**
   - `gh issue create` で Issue を作成する
   - 作成した Issue の URL を出力する

5. **知識の記録**
   - `raw/issues/YYYY-MM-DD_[issue-number]/[title].md` に記録する
   - Issue の詳細・受入基準・設計メモを含める
