# タスクリスト（Issue #12: TODO カテゴリ機能）

## 実装タスク
- [x] T1: `prisma/schema.prisma` に `TodoCategory` モデルと `Todo.categoryId` を追加しマイグレーション生成（見積: 1h）
- [x] T2: `app/actions/categories.ts` に `createCategory` / `deleteCategory` を追加（見積: 1h、依存: T1）
- [x] T3: `app/actions/todos.ts` に `assignCategory` を追加（見積: 1h、依存: T1）
- [x] T4: `app/components/AddCategoryForm.tsx` を新規作成（見積: 0.5h、依存: T2）
- [x] T5: `app/components/CategoryList.tsx` を新規作成（絞り込みGETフォーム + 一覧・削除）（見積: 1h、依存: T2）
- [x] T6: `app/components/TodoList.tsx` を更新（categories props 追加、割り当てselect追加）（見積: 0.5h、依存: T3）
- [x] T7: `app/page.tsx` を更新（searchParams対応、todos/categories並列取得、新規コンポーネント組み込み）（見積: 1h、依存: T4, T5, T6）

## テストタスク
- [x] T8: `createCategory` / `deleteCategory` の Unit テスト（見積: 1h、依存: T2）
- [x] T9: `assignCategory` の Unit テスト（見積: 1h、依存: T3）
- [x] T10: カテゴリ削除時の DB SetNull 制約テスト（`tests/schema.test.ts` 拡張）（見積: 0.5h、依存: T1）
- [x] T11: `AddCategoryForm` の Component テスト（見積: 0.5h、依存: T4）
- [x] T12: `TodoList` / `page.tsx` の既存テスト更新 + 絞り込みのテスト（見積: 1h、依存: T6, T7）

## レビュー対応タスク（ラウンド2）
- [x] T14: `app/page.tsx` の `Home` シグネチャ修正（`next build` の型エラー解消, codex-review Must）
- [x] T15: `assignCategory` を `prisma.$transaction` でアトミック化（TOCTOU解消, review-agent Should）
- [x] T16: `deleteCategory` / `schema.prisma` に設計意図のコメントを追加

## ドキュメントタスク
- [ ] T13: `raw/` に Issue #12 実装コンテキストを記録する（`/create-pr` フェーズで `changes.md` として生成）
