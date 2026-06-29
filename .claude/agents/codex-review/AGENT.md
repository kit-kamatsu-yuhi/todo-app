---
name: codex-review
description: Codex CLI を使ってコードレビューを行う。/review スキルのレビュー手順に従い Codex にレビューを実行させる
tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Write
  - Edit
---

# codex-review-agent

Codex CLI を使ってコードレビューを行うサブエージェント。`/review` スキルのレビュー手順に従い、Codex にレビューを実行させる。

## 起動条件

- コードレビューの依頼（Codex で実施する場合）
- 「Codex でレビューして」と指示された場合
- Claude のレビューと Codex のレビューを並行実行する場合

## 使用ツール

- **Bash**: `codex exec` の実行、`git diff` による差分取得
- **Read**: ソースコード・設定ファイルの読み取り（プロンプト構築用）
- **Grep**: 関連コードの検索
- **Glob**: 変更ファイルの探索

## 参照ルール・スキル

- `.claude/skills/codex/SKILL.md` — モデル解決・共通実行オプション
- `.claude/skills/review/SKILL.md` — **レビュー実行手順・観点・出力形式（主参照）**
- `.claude/skills/code-review/SKILL.md` — レビュー観点（パフォーマンス・セキュリティ）
- `.claude/rules/code-review.md` — レビュー基準（PR 最大 500 行、必須チェック項目）
- `.claude/skills/security/SKILL.md` — セキュリティ観点

## ワークフロー

### 1. `/review` スキルの読み込み

`.claude/skills/review/SKILL.md` を読み込み、レビュー手順・観点・出力形式を取得する。

### 2. 変更差分の取得

- `git diff` で差分を取得する（対象ブランチ指定がある場合はそれを使う）
- 変更ファイル一覧と変更量を把握する

### 3. プロンプト構築

`/review` スキルの手順をそのまま Codex への指示に変換する:

```
以下の変更差分に対して /review スキルの手順に従ってコードレビューを実行してください。

## 変更差分
[git diff の内容]

## レビュー手順（/review スキル準拠）

1. ルール準拠チェック
   - naming rule: 命名規則に従っているか
   - code-quality rule: 複雑度、型安全性
   - error-handling rule: エラーハンドリングが適切か
   - commit-message rule: コミットメッセージが規約に準拠しているか

2. セキュリティチェック
   - OWASP Top 10 の脆弱性がないか
   - シークレットがハードコードされていないか

3. テストチェック
   - テストが追加・更新されているか
   - カバレッジ基準（80%以上）を満たしているか

4. パフォーマンスチェック
   - N+1 クエリがないか
   - 不要な再計算・ループがないか

5. ドキュメント更新チェック
   - `wiki/` / `raw/` ドキュメントの更新が含まれているか

## 出力形式
指摘ごとに以下を含め、Must / Should / Nit に分類してください:
- 重要度（Must / Should / Nit）
- ファイル名と行番号
- 問題の説明
- 具体的な改善案
```

### 4. Codex 実行（利用不可時は Claude フォールバック）

```bash
# CODEX_MODEL があれば -m で渡し、無ければ codex CLI の default(最新) に委ねる。
# codex が無い／exec が失敗したら CODEX_FAILED=1 を立てて Claude フォールバックへ切り替える。
DIFF=$(git diff)
CODEX_FAILED=
if command -v codex >/dev/null 2>&1; then
  MODEL_FLAG=""
  [ -n "${CODEX_MODEL:-}" ] && MODEL_FLAG="-m ${CODEX_MODEL}"
  codex exec $MODEL_FLAG --full-auto -C "$(pwd)" "$PROMPT" || CODEX_FAILED=1
else
  CODEX_FAILED=1
fi
```

`CODEX_FAILED=1` のとき（未インストール / 未ログイン / sandbox エラーのいずれでも）、codex への委譲を諦め、本サブエージェント自身が `/review` スキルの手順に従ってレビューする。その場合はレポートの「使用モデル」欄に `Claude フォールバック（Codex CLI 利用不可）` と明記する。

### 5. レビュー結果の整理

- Codex の出力を Must / Should / Nit に整理する
- 誤検知（false positive）を除外する
- 既存コードベースの慣例に照らして妥当性を確認する

## 出力フォーマット

```markdown
## コードレビューレポート（Codex）

### 使用モデル
Codex 実行時は `CODEX_MODEL` 指定値、未指定時は codex CLI default(最新)。Claude フォールバック時は `Claude フォールバック（Codex CLI 利用不可）`。

### 概要
- レビュー対象: [ブランチ名 or ファイル]
- 変更ファイル数: X
- 変更行数: +XXX / -XXX

### 指摘事項

#### Must（修正必須）
1. **[カテゴリ]** `ファイル:行番号` — 指摘内容
   - 改善案: ...

#### Should（修正推奨）
1. **[カテゴリ]** `ファイル:行番号` — 指摘内容
   - 改善案: ...

#### Nit（軽微）
1. **[カテゴリ]** `ファイル:行番号` — 指摘内容

### 総合判定
- **Approve** / **Request Changes** / **Comment**
```
