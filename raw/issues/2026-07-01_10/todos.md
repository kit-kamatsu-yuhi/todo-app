# タスクリスト — Issue #10 TODO 追加・削除機能

## 実装タスク
- [x] T1: `app/actions/todos.ts` に `createTodo`（getSession 検証 / zod trim+min1+max255 / position=max+1 採番 / prisma.todo.create / revalidatePath('/')）（見積もり: 1.5h）
- [x] T2: `app/actions/todos.ts` に `deleteTodo`（getSession 検証 / 未ログインは redirect('/login') / `deleteMany({ where: { id, userId } })` で所有者チェック / revalidatePath('/')）（見積もり: 1h）
- [x] T3: `app/components/AddTodoForm.tsx`（'use client' / useActionState(createTodo, null) / input name="title" required / role="alert" エラー表示 / pending disable / 成功時に入力欄クリア）（見積もり: 1h）
- [x] T4: `app/components/TodoList.tsx` + TodoItem（`<ul>` 描画 / 各項目に `<form action={deleteTodo}>` + hidden id + 削除ボタン）（見積もり: 1h）
- [x] T5: `app/page.tsx` を async Server Component 化（getSession→null なら redirect('/login') / findMany where userId orderBy position asc / AddTodoForm + TodoList + 既存 logout 合成）（見積もり: 1h）

## テストタスク
- [x] T6: `tests/todos/actions.test.ts`（統合・主カバレッジ）
  - createTodo: 正常作成 & userId 紐づけ保存（AC1）
  - createTodo: 空文字でエラー & 未保存（AC2）
  - createTodo: 空白のみでエラー & 未保存（AC2）
  - createTodo: 未ログインでエラー & 未保存（AC5）
  - createTodo: position が max+1 で採番される
  - deleteTodo: 自分の TODO を削除 & DB から消える（AC3）
  - deleteTodo: 他ユーザーの id では削除されず件数不変（AC4）
  - deleteTodo: 未ログインで redirect('/login') & DB 不変（AC5）
  （見積もり: 2h）
- [x] T7: `tests/todos/AddTodoForm.test.tsx`（input+ボタン描画 / エラー時 role="alert" 表示）（見積もり: 1h）
- [x] T8: `tests/page.test.tsx` 更新（getSession + prisma モック / `render(await Home())` / 見出し + TODO 一覧表示）（見積もり: 0.5h）

## ドキュメントタスク
- [x] T9: `raw/conversations/2026-07-01_issue-10-todo-crud.md` に実装コンテキストを記録

## 受入基準トレース
- AC1（追加→即時反映&保存）: T6（DB）+ 手動（UI）
- AC2（空タイトル→エラー&未保存）: T6 + T7
- AC3（自分の削除→消える&DB削除）: T6 + 手動
- AC4（他人の id→認可エラー）: T6（deleteMany 複合条件）
- AC5（未ログイン→ログイン誘導）: T6（Action 拒否）+ 手動（middleware redirect）
