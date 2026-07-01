# Issue #10 TODO 追加・削除機能 実装

- date: 2026-07-01
- topic: ログインユーザーに紐づく TODO の一覧・追加・削除を Server Actions + revalidate で実装

## 実施内容

- `feature/10-todo-crud`（worktree `.claude/worktrees/10-todo-crud`、base `origin/main` 86a7a21）で実装
- 依存 #9（email-auth）は PR #15 でマージ済み。auth 基盤（`getSession()` / `middleware.ts` / `Session` モデル）を再利用
- 実装ファイル:
  - `app/actions/todos.ts` — `createTodo`（認証再検証 → zod `trim().min(1).max(255)` → `aggregate` で position 採番 → `create` → `revalidatePath('/')`）、`deleteTodo`（認証再検証 → `deleteMany({ where: { id, userId } })` 所有者チェック → revalidate）
  - `app/components/AddTodoForm.tsx` — `'use client'`、`useActionState`、`role="alert"` エラー表示、成功時に入力欄リセット
  - `app/components/TodoList.tsx` — Server Component、一覧 + 各項目の削除フォーム
  - `app/page.tsx` — async Server Component 化（未ログインは `/login` redirect、`userId` で `findMany`）
- テスト: `tests/todos/actions.test.ts`（統合 12）/ `tests/todos/AddTodoForm.test.tsx`（3）/ `tests/page.test.tsx`（更新 2）→ 全 43 passed
- スキーマ変更・マイグレーションなし（`Todo` モデルは #8 で追加済み）

## 決定事項

- **base ブランチ**: #9 マージ済みのため `origin/main` から分岐（stacked PR は不要）
- **所有者チェック**: `deleteMany` の `id`+`userId` 複合条件で TOCTOU を回避（findUnique+分岐は使わない）
- **多層防御**: middleware に加え各 Server Action 内で `getSession()` を再検証
- **position 採番**: 追加時に `max(position)+1`（ユーザー単位、初回 0）。同時追加の競合はリスク受容（並べ替えは #11/#12）
- **`.eslintrc.json` に `"root": true` 追加**: worktree が親リポジトリ配下にネストするため ESLint が上位設定まで遡り `@next/next` を二重ロードして `npm run lint` が落ちる問題への対処。全作業を worktree で行う運用（worktree.md）では有効で、CI（フラット clone）では無害なため残す判断
- **package-lock.json**: `npm install` によるキャレット除去差分は Issue スコープ外のため `origin/main` に復帰

## レビュー対応（codex-review + review-agent の指摘を反映）

- M-1: `AddTodoForm` の `useEffect` が初回マウントでも `form.reset()` する問題 → `submittedRef` で初回と送信成功を分離
- M-2: 成功時クリア／position の userId スコープ／自分削除+他人残存の複合ケースのテストを追加
- M-3: 255文字超のエラーメッセージを `too_big` 判定で出し分け（plan と整合）
- N-2: `createTodo` のエラーログに `userId` を追加（plan §7・error-handling 規約）
- 空文字 `id` を deleteTodo の早期 return ガードに追加
- 受入基準判定: AC1〜AC5 全 GREEN（自動検証可能部分）、セキュリティ基準 5 項目充足

## 現在のプロジェクト状態

- 実装・テスト・レビュー完了、tsc/lint/test すべて green（43 passed）
- 未コミット（Phase C: PR 作成待ち）
- 手動確認の残余: AC1/AC3 の UI 即時反映、AC5 の middleware redirect（PR チェックリスト行き）

## 未解決事項

- カバレッジ数値は `@vitest/coverage-v8` 未導入のため未計測（分岐はソース照合で網羅済み。数値要件があれば devDependency 追加が必要）
- 完了トグル（`completed`）・並べ替え（`position` 更新）は本 Issue スコープ外（#11/#12 想定）
