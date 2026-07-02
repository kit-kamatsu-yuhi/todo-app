# Issue #11 TODO 編集・並び替え機能 実装

- date: 2026-07-02
- topic: TODO のタイトルインライン編集・完了切替・並び替え（position 永続化）を Server Actions で実装

## 実施内容

- `feature/11-todo-edit-reorder`（worktree `.claude/worktrees/11-todo-edit-reorder`、base `main` d4be69d）で実装
- 依存 #10（todo-crud）は PR #16 でマージ済み。`Todo` モデルの `completed`/`position`/`updatedAt` は既に存在するため、今回の DB 変更は一意制約の追加のみ
- Codex CLI をこのセッション中にインストール（`npm install -g @openai/codex`）したが、`codex login` は未完了のままだったため `/codex-team` 内の codex-implement/codex-test/codex-review エージェントはすべて Claude フォールバックで動作した
- 実装ファイル:
  - `app/actions/todos.ts` — `updateTodoTitle`（zod検証 → `updateMany({id,userId})` 所有者チェック → revalidate）、`toggleTodo`（`findFirst({id,userId})` で所有権確認 → `completed` 反転）、`moveTodo`（対話的トランザクションで隣接 `position` をアトミックに入れ替え）
  - `app/components/TodoTitleEditor.tsx` — 新規 `'use client'` コンポーネント。表示⇄編集をローカル state で切替、`useActionState` で `updateTodoTitle` にバインド
  - `app/components/TodoList.tsx` — 完了切替フォーム・`TodoTitleEditor`・▲▼並び替えフォーム（先頭/末尾 disabled）を追加
  - `prisma/schema.prisma` / `prisma/migrations/20260702001533_add_todo_position_unique/` — `Todo` に `@@unique([userId, position])` を追加
- テスト: `tests/todos/actions.test.ts`（追記、同時実行検証含む）/ `tests/todos/TodoTitleEditor.test.tsx`（新規）/ `tests/todos/TodoList.test.tsx`（新規）→ 全 69 passed

## 決定事項

- **並び替え UI は ▲▼ ボタン方式**: dnd-kit 導入案とボタン方式をユーザーに提示し選択してもらった。新規 npm 依存を追加せず、既存の delete フォームと同じ progressive enhancement パターンで実装・テストできることを重視
- **`updateTodoTitle` は他人の TODO 操作時に `{error}` を返すが `toggleTodo`/`moveTodo` は no-op**: `updateTodoTitle` のみ `useActionState` でエラー表示 UI を持つため対称的にエラーを返せる。他2つは `deleteTodo` の既存方針（無変更で return）を踏襲
- **`moveTodo` は対話的トランザクション（`prisma.$transaction(async (tx) => {...})`）**: 読み取り（`findFirst`×2）と書き込み（`update`×3）を同一トランザクション内に統一し、同時実行時の position 読み取り不整合を防ぐ
- **`(userId, position)` に DB 一意制約を追加**: アプリケーションロジックだけでなく DB レベルでも position の重複を防ぐ防御的な設計
- **position 入れ替えは一時値 `-1` 経由の3ステップ**: 一意制約下で2件を直接入れ替えると中間状態で制約違反になるため、`createTodo` が常に 0 以上を採番する前提を利用し `-1` を安全な退避値とした

## レビュー対応（codex-review + review-agent、2ラウンド）

### ラウンド1
- codex-review: Must なし、Should 4件・Nit 3件 → **Approve**
- review-agent: **Must 3件** → **Request Changes**
  1. `package.json` の `@vitest/coverage-v8` がキャレット付き（依存管理方針違反）
  2. `moveTodo` が read-then-write の非アトミック構成でレースコンディションの余地がある
  3. `Todo.position` に DB レベルの一意制約がない

### 修正内容
- `@vitest/coverage-v8` を完全固定バージョン `3.2.6` に変更
- `moveTodo` を対話的トランザクションに変更
- `Todo` に `@@unique([userId, position])` を追加、マイグレーション生成
- `moveTodo` の同時実行（`Promise.all`）を検証するテスト2件を追加

### ラウンド2（フォローアップレビュー）
- codex-review: Must なし → **Approve**（`$transaction` のロールバック挙動・`tempPosition=-1` の安全性を実装レベルで確認済みと報告）
- review-agent: Must なし → **Approve**（`$transaction` の完全直列化を検証スクリプトで確認したと報告）
- 受入基準（AC1〜AC5）・セキュリティ基準（4項目）すべて GREEN（acceptance-criteria-agent 判定）

## 現在のプロジェクト状態

- 実装・テスト・レビュー（2ラウンド）完了、tsc/lint/test すべて green（69 passed）
- `raw/issues/2026-07-01_11/` に `plan.md` / `todos.md`（完了チェック更新済み）/ `changes.md` を配置
- コミット済み・`feature/11-todo-edit-reorder` を origin に push・**PR #17 作成済み**（`Fixes #11`）
- 手動テストチェックリストは PR 本文に記載、実機確認は未実施（レビュアー/ユーザーの手動確認待ち）

## 未解決事項

- `codex login` が未完了のまま。ユーザーが ChatGPT Codex 契約・組織参加済みとのことなので、次回セッションでログインが完了すれば `/codex-team` の各エージェントが実際に Codex CLI（`codex exec`）に処理を委譲するようになる
- `toggleTodo` は `moveTodo` と異なり read-then-write のままで、`completed` の同時反転による打ち消し合いのリスクは許容範囲としてレビューで合意済み（コード上に明記はしていない）
- `.claude/worktrees/9-email-auth`（PR #15 マージ済み）が未削除のまま残っている。今回の作業対象外だが、次回の worktree 整理（`git worktree remove` / `git worktree prune`）で片付ける余地あり
