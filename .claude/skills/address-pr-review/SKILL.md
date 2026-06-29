---
name: address-pr-review
description: |
  PRレビューコメントの取得・対応・記録。PR URLを受け取り、レビュー内容とコードを表示し、対応後に `raw/` に記録を残す。
  TRIGGER when: 「レビュー対応して」「PR のコメント直して」「レビュー指摘を修正して」など、PR レビューコメントへの対応を依頼されたとき。PR URL を渡されたとき。
  DO NOT TRIGGER when: 新規レビューの実施（→ review スキル）、PR 作成（→ create-pr スキル）。
user_invocable: true
command: /address-pr-review
argument-hint: "<PR URL (例: https://github.com/org/repo/pull/123)>"
---

# PR レビュー対応

$ARGUMENTS の PR レビューコメントを取得し、対応を実施する。

## 手順

### 1. PR URL のパース

- $ARGUMENTS から PR URL を受け取る
- URL から `owner`, `repo`, `number` を抽出する
- 例: `https://github.com/tieups/weclip.link/pull/8255` → `owner=tieups`, `repo=weclip.link`, `number=8255`

### 2. レビューコメントの取得

以下の3つの API を実行してレビュー情報を収集する。

#### 2a. インラインレビューコメント

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
```

各コメントから以下を抽出する:
- `user.login` — レビュアー名
- `created_at` — コメント日時
- `path` — 対象ファイルパス
- `line`（または `original_line`）— 対象行番号
- `body` — コメント本文
- `diff_hunk` — レビュー時点のコード差分
- `commit_id` — 対象コミット

#### 2b. レビューレベルのコメント

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate
```

`body` が空でないもののみ抽出する。各レビューから以下を使用する:
- `user.login` — レビュアー名
- `state` — レビュー状態（APPROVED, CHANGES_REQUESTED, COMMENTED 等）
- `submitted_at` — 提出日時
- `body` — コメント本文

#### 2c. PR メタデータ

```bash
gh pr view {number} --repo {owner}/{repo} --json title,body,state,author
```

### 3. レビュー内容の提示

取得した全レビューコメントを以下の形式で一覧表示する:

```
## レビュー #<N>
- **レビュアー**: <user.login> (<bot / 人間>)
- **日時**: <created_at>
- **ファイル**: <path>:<line>

### レビュー時点のコード
\`\`\`
<diff_hunk>
\`\`\`

### コメント
<body>
```

表示時の注意:
- bot によるレビュー（GitHub Actions, Codex, dependabot 等 `[bot]` が付くユーザー）と人間によるレビューを区別して表示する
- レビューレベルのコメント（2b で取得したもの）は「全体コメント」として別セクションに表示する
- コメントは時系列順に番号を振る

### 4. 対応方針の確認

各レビューコメントについて、ユーザーに対応方針を確認する。選択肢は以下の3つ:

| 方針 | 説明 |
|------|------|
| **修正する** | コードを修正して対応する |
| **対応不要** | 修正しない（理由を記録する） |
| **回答済み** | PR 上で既に回答済み |

ユーザーが一括で方針を指示する場合もある。例:
- 「1はこう直して、2は対応不要、3は回答済み」
- 「全部対応して」
- 「botのコメントは無視して、人間のだけ対応」

### 5. レビュー対応の実施

修正実施時は **Skill ツールで `/codex-team review` を必ず呼び出す**（スキップ不可）。Claude が直接コードを編集して完結させてはならない。

`/codex-team review` は内部で以下を実行する:
- Claude（指揮官）が修正方針を決定
- codex-implement / codex-test で修正を実行
- codex-review + review-agent で修正結果を確認

修正の基本ルール:
- 修正対象のファイルは、PR のブランチ上で編集する
- **レビュー項目ごとにコミットを作成し、コミット直後に当該レビューコメントへ返信する（必須・スキップ不可）**
  - 返信形式: `対応しました（<commit hash>）。<対応内容の一言>`
  - 返信コマンド: `gh api repos/{owner}/{repo}/pulls/comments/{comment_id}/replies -X POST -f body="..."`
- コミットメッセージは Conventional Commits 準拠で記述する（`fix`, `refactor` 等）
- 複数の修正が同一ファイルの近接箇所に関わる場合は、1コミットにまとめ返信もまとめてよい

### 6. レビュー対応記録の保存

対応完了後、以下のパスにレビュー対応記録を保存する:

- **保存先**: `raw/issues/YYYY-MM-DD_<PR番号>/reviews.md`
- PR に関連する Issue 番号がある場合は `YYYY-MM-DD_<Issue番号>/reviews.md` を優先する

#### 記録フォーマット

```markdown
# PR #<number> レビュー対応記録

- date: YYYY-MM-DD
- pr: <PR URL>
- title: <PR title>
- reviewers: <reviewer list>

## レビュー <N>: <対象ファイル>

### レビュー対象コード

\`\`\`
<diff hunk from review>
\`\`\`

### レビュー内容

<reviewer>: <comment body>

### 対応

- **方針**: 修正 / 対応不要 / 回答済み
- **対応内容**: <what was done>
- **コミット**: <commit hash> (if applicable)
```

### 7. レビュー知見の蓄積（必須）

対応完了後、レビュー指摘とその対応内容を汎化して `wiki/pages/reviews/` に保存する。

- 保存先: `wiki/pages/reviews/<topic>.md`（トピック別にファイルを分ける）
- 既存のトピックファイルがあれば追記、なければ新規作成する
- 個別の Issue/PR 固有の情報は除去し、再利用可能な知見として汎化する

#### 知見の保存フォーマット

```markdown
## <知見タイトル>

- date: YYYY-MM-DD
- source: PR #<number>

### 指摘内容
（何が指摘されたか、汎化して記述）

### 対応パターン
（どう対応すべきか）

### 適用場面
（どのような場面でこの知見が役立つか）
```

### 8. サマリー出力

全対応完了後、以下のサマリーを出力する:

- 対応したレビュー数 / 全レビュー数
- 方針別の内訳（修正: N件、対応不要: N件、回答済み: N件）
- 作成したコミットの一覧（ハッシュとメッセージ）
- 保存したレビュー記録ファイルのパス
