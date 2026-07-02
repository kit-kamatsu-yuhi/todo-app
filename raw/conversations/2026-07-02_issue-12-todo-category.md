# Issue #12 TODO カテゴリ機能 実装

- date: 2026-07-02
- topic: `TodoCategory` モデルを追加し、カテゴリの作成・削除・TODOへの割り当て・絞り込みを実装

## 実施内容

- `feature/12-todo-category`（worktree `.claude/worktrees/12-todo-category`、base `main` c455ad7）で実装
- 依存 #8, #10 はマージ済み
- **今回のセッションから Codex CLI が実際に稼働**（`npm install -g @openai/codex` → `codex login` 完了）。codex-implement/codex-test/codex-review は実際に `codex exec`（モデル `gpt-5.5` 等）に処理を委譲した（一部、要件が明確な小修正は Codex 委譲を省略し Claude が直接実装）
- 実装ファイル:
  - `prisma/schema.prisma` / `prisma/migrations/20260702022804_add_todo_category/` — `TodoCategory` モデル追加、`Todo.categoryId`（nullable, `onDelete: SetNull`）追加
  - `app/actions/categories.ts`（新規） — `createCategory` / `deleteCategory`
  - `app/actions/todos.ts` — `assignCategory` 追加（Todo・Category両方の所有権確認を `$transaction` 内で実施）
  - `app/components/AddCategoryForm.tsx`（新規, Client） — `AddTodoForm` と同パターン
  - `app/components/CategoryList.tsx`（新規, Server） — GETフォームでの絞り込み + カテゴリ一覧・削除
  - `app/components/TodoList.tsx` — `categories` props 追加、割り当て用select追加
  - `app/page.tsx` — `searchParams` 対応（Next.js 15 非同期props）、`categoryId` 絞り込み
- テスト: `tests/categories/actions.test.ts`（9）/ `tests/categories/AddCategoryForm.test.tsx`（3）/ `tests/categories/CategoryList.test.tsx`（5）/ `tests/todos/actions.test.ts` に `assignCategory`（5）/ `tests/schema.test.ts` に SetNull検証（1）/ `tests/page.test.tsx`・`tests/todos/TodoList.test.tsx` 更新 → 全 97 passed

## 決定事項

- **カテゴリ削除時の `Todo.categoryId` null化は DB の FK 制約（`onDelete: SetNull`）に委ねる**: アプリ側で個別に null 更新するロジックを書かない。`tests/schema.test.ts` で DB レベルの動作を直接検証
- **絞り込みは `<form method="get">` によるブラウザのネイティブ GET 遷移**: Server Action も JS も不要。query param（`?category=<id>`）が状態のソースオブトゥルース
- **カテゴリ割り当ても plain `<select>` + 送信ボタンの form**（`assignCategory`）: 新規クライアントコンポーネントは作成側の `AddCategoryForm` のみに限定
- **`assignCategory` は Todo・Category 双方の所有権を確認**: カテゴリの `findFirst` と Todo の `updateMany` を同一トランザクション内で実施し、他人のカテゴリへの参照を防ぐ
- **カテゴリ名に一意制約を付けない**: Issue 要件外のため許容する判断をスキーマにコメントで明記

## レビュー対応（codex-review + review-agent、2ラウンド）

### ラウンド1
- codex-review: **Must 1件 → Request Changes**
  - `app/page.tsx` の `Home({ searchParams }: {...} = {})` が Next.js 15 の `PageProps` 制約を満たさず `next build` が型エラーで失敗（`tsc --noEmit` では検出できず、実際に `next build` を実行して判明した点が重要な教訓）
- review-agent: **Should 1件 → Approve**
  - `assignCategory` のカテゴリ所有権確認（`findFirst`）と Todo 更新（`updateMany`）が別クエリで TOCTOU の余地がある（Issue #11 の `moveTodo` と同系統の指摘）

### 修正内容
- `Home` のシグネチャを「引数は必須、`searchParams` プロパティのみ optional」に修正
- `assignCategory` を `prisma.$transaction(async (tx) => {...})` でアトミック化
- `deleteCategory` / `schema.prisma` に設計意図のコメントを追加

### ラウンド2（フォローアップレビュー）
- codex-review: Must なし → **Approve**（`next build` 成功を実機確認）
- review-agent: Must/Should なし → **Approve**（トランザクション化を実装レベルで確認）
- 受入基準（AC1〜AC5）・セキュリティ基準6項目すべて GREEN（acceptance-criteria-agent 判定）

## 現在のプロジェクト状態

- 実装・テスト・レビュー（2ラウンド）完了、tsc/next build/lint/test すべて green（97 passed）
- `raw/issues/2026-07-02_12/` に `plan.md` / `todos.md`（完了チェック更新済み）/ `changes.md` を配置
- コミット済み・`feature/12-todo-category` を origin に push・**PR #18 作成済み**（`Fixes #12`）

## 未解決事項

- worktree の `node_modules` が複数エージェントの並行作業中に断続的に破損する現象が今回も発生した（`prisma` の wasm 欠損、`source-map-js` の空ディレクトリ等）。各エージェントがその場で `npm install <pkg> --no-save` 等で自己修復して対応したが、根本原因（並行 install の競合か、worktree 特有のシンボリックリンク問題か）は特定していない。次回同様の問題が頻発するなら `node_modules` を worktree ごとに独立させる運用（現状もそうだが）や、実装フェーズ前に一度 `npm ci` するステップを codex-team のワークフローに組み込むことを検討する余地がある
- `next build` の型エラーは `tsc --noEmit` では検出できず、Next.js の `PageProps` 制約は `next build` 実行時にのみチェックされることが分かった。今後 `searchParams`/`params` を使うページを実装する際は、レビュー段階で必ず `next build` を実行するチェックリスト項目として明記する価値がある
