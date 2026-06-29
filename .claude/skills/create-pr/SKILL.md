---
name: create-pr
description: |
  PR作成。Linear Walkthrough生成→Mermaid フローチャートをPR本文に直接記載→既存PRテンプレートを尊重してPRを作成する。全PRで統一的な品質を担保する。
  TRIGGER when: 「PR作れ」「PR作成して」「PRお願い」「プルリク作って」など、PR作成を依頼された場合。
  DO NOT TRIGGER when: PR のレビュー依頼（→ review スキル）、PR コメントへの対応（→ address-pr-review スキル）。
user_invocable: true
command: /create-pr
argument-hint: "[Issue番号 or 説明]"
---

# PR 作成

変更をコミット済みの状態から、Linear Walkthrough 付きの PR を作成する。

## 前提条件

- 変更がコミット済みであること
- feature ブランチで作業中であること

## 手順

### 1. Linear Walkthrough 生成

`/walkthrough` を実行し、実装内容の構造解説ドキュメントを生成する。

- 出力先: `raw/issues/YYYY-MM-DD_<issue番号>/changes.md`
- コミット済みの変更に対して `git diff $(git merge-base HEAD origin/HEAD)...HEAD` で差分を取得するため、実装コミット後に実行する（main 以外のブランチから切った場合にも対応）
- changes.md には Mermaid フローチャートが必須で含まれる

### 2. Walkthrough コミット

changes.md をコミットする。

### 3. リモートに push

ユーザーの承認を得てから push する。

### 4. PR 本文の構成

#### 既存テンプレートの確認

`.github/pull_request_template.md` の存在を確認する。

#### テンプレートがある場合

テンプレートの構成をベースにしつつ、以下のセクションを追加・挿入する:

- `## Issue` — `Fixes #<issue番号>`（テンプレートになければ追加）
- `## Changes` — Mermaid フローチャート + changes.md リンク + 変更箇条書き（テンプレートになければ追加）
- **Mermaid 構文の注意**: PR 本文の Mermaid は GitHub がレンダリングする。subgraph タイトルにノード形状記法（`[( )]` 等）を使わないこと。詳細は `uml` スキルの「GitHub 互換 Mermaid 構文ルール」を参照
- テンプレートに既存の Test plan / チェックリスト等はそのまま活かす

#### テンプレートがない場合

デフォルトテンプレートを使用する:

```markdown
## Issue

Fixes #<issue番号>

## Changes

```mermaid
<changes.md 内の Mermaid フローチャートを転記>
```

変更箇所の構造解説: [changes.md](リンク)

- 変更内容の箇条書き

## Test plan

- [ ] テスト項目...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 5. PR 作成

`gh pr create` で PR を作成する。

**必須要素:**
- PR 本文に `## Issue` セクションで `Fixes #<issue番号>` を記載する（マージ時に Issue を自動クローズ）
- `## Changes` セクションに Mermaid コードブロックを直接記載する（GitHub がネイティブレンダリング）
- changes.md へのリンクを含める

**任意要素（実装 PR の場合）:**
- 受入基準の充足状況
- 手動テストチェックリスト

### 6. raw/ コンテキスト記録

`raw/` にコンテキストを記録する（doc-management ルール参照）。

## 他スキルからの呼び出し

| 呼び出し元 | タイミング |
|-----------|-----------|
| `start-issue` | Phase C（実装/テスト/レビュー完了後） |
| 直接呼び出し | ドキュメント PR、リファクタリング PR 等 |

## フォールバック

`/create-pr` 失敗時は `gh pr create` 直接実行を許可する（block-direct-gh-pr.sh がブロックするが、その場合はユーザーに手動で許可してもらう）。
