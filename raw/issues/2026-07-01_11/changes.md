# Issue #11: TODO 編集・並び替え機能 — 実装解説

- date: 2026-07-02
- branch: `feature/11-todo-edit-reorder`
- base: `main`（merge-base: `d4be69d`）

## 概要

TODO のタイトルインライン編集、完了/未完了の切り替え、並び順の変更を Server Actions で実装した。並び替えは ▲▼ ボタンで隣接する TODO と `position` を入れ替える方式を採用し、dnd-kit 等の新規 npm 依存は追加していない。

## 変更ファイル

| ファイル | 種別 | 内容 |
|---|---|---|
| `app/actions/todos.ts` | 実装 | `updateTodoTitle` / `toggleTodo` / `moveTodo` を追加 |
| `app/components/TodoTitleEditor.tsx` | 新規 | インライン編集用クライアントコンポーネント |
| `app/components/TodoList.tsx` | 実装 | 完了切替・並び替えフォーム、`TodoTitleEditor` を組み込み |
| `prisma/schema.prisma` | DB | `Todo` に `@@unique([userId, position])` を追加 |
| `prisma/migrations/20260702001533_add_todo_position_unique/` | DB | 上記の一意インデックスを追加するマイグレーション |
| `package.json` / `package-lock.json` | 依存 | `@vitest/coverage-v8`（完全固定バージョン）を devDependency として追加 |
| `vitest.config.ts` | テスト基盤 | `fileParallelism: false` を追加（複数テストファイルが共有 SQLite に同時アクセスする際の競合対策） |
| `tests/todos/actions.test.ts` | テスト | `updateTodoTitle` / `toggleTodo` / `moveTodo` の Unit テストを追加（同時実行検証を含む） |
| `tests/todos/TodoTitleEditor.test.tsx` | テスト | 新規コンポーネントのテスト |
| `tests/todos/TodoList.test.tsx` | テスト | 先頭/末尾の disabled 制御・完了表示分岐のテスト |

## アーキテクチャ概要

`app/page.tsx`（Server Component）が `prisma.todo.findMany` で一覧を取得し `TodoList` に渡す。`TodoList` は各 TODO を、完了切替フォーム・タイトル編集コンポーネント・▲▼並び替えフォーム・削除フォームの4パーツで描画する。完了切替・並び替え・削除は JS 不要な plain `<form action={ServerAction}>` で progressive enhancement を保ち、タイトルのインライン編集（表示⇄入力欄の切替）のみクライアント側の状態が必要なため `TodoTitleEditor`（Client Component）として切り出した。

## 処理フロー

```mermaid
flowchart TD
    A[ユーザー操作] --> B{操作の種類}
    B -->|タイトル編集| C[TodoTitleEditor: 編集ボタンで入力欄表示]
    C --> D[保存: useActionState経由でupdateTodoTitle呼び出し]
    D --> E{getSession確認}
    E -->|未ログイン| F[エラー: ログインが必要です]
    E -->|OK| G{TitleSchema検証}
    G -->|空/空白/255文字超| H[エラーメッセージ表示・編集モード継続]
    G -->|OK| I["updateMany({id, userId}, {title})"]
    I -->|count=0: 他人のTODO| J[エラー: TODOが見つかりません]
    I -->|成功| K[revalidatePath → 表示モードに復帰]

    B -->|完了切替| L[form action=toggleTodo]
    L --> M{getSession確認}
    M -->|未ログイン| N[/loginへredirect]
    M -->|OK| O["findFirst({id, userId})"]
    O -->|見つからない: 他人のTODO| P[no-op]
    O -->|見つかった| Q[completedを反転してupdate]
    Q --> R[revalidatePath]

    B -->|並び替え ▲▼| S[form action=moveTodo]
    S --> T{getSession確認}
    T -->|未ログイン| N
    T -->|OK| U[direction をenumで検証]
    U -->|不正値| V[no-op]
    U -->|OK| W["prisma.$transaction: 対話的トランザクション開始"]
    W --> X["tx.findFirst(current)"]
    X -->|見つからない: 他人のTODO| Y[no-op トランザクション内でreturn]
    X -->|見つかった| Z["tx.findFirst(neighbor: position±1)"]
    Z -->|見つからない: 先頭/末尾| Y
    Z -->|見つかった| AA["current→一時position=-1"]
    AA --> AB["neighbor→currentの元position"]
    AB --> AC["current→neighborの元position"]
    AC --> R
```

## エントリーポイント

- 一覧描画: `app/page.tsx:8-27`（`prisma.todo.findMany({ where: { userId }, orderBy: { position: 'asc' } })` → `TodoList` に渡す）
- 各操作の起点: `app/components/TodoList.tsx:12-34` の `todos.map` 内で、各 TODO ごとに4つのフォーム/コンポーネントを描画

## データフロー

1. `page.tsx` がサーバー側で最新の TODO 一覧を取得し、HTML として初回描画する。
2. ユーザーがボタン操作すると、対応する Server Action（`toggleTodo`/`moveTodo`/`deleteTodo`）または `useActionState` 経由の Action（`updateTodoTitle`）が呼ばれる。
3. 各 Action は `getSession()` で認証を再検証し、`userId` を複合条件に含めた Prisma クエリで所有権を確認してから DB を更新する。
4. 成功時は `revalidatePath('/')` を呼び、Next.js が `page.tsx` を再実行してキャッシュを更新する。
5. `TodoTitleEditor` は自身のローカル state（`isEditing`）でのみ表示⇄編集を切り替えるため、`revalidatePath` によるサーバー側再取得と競合しない。

## 主要な判断分岐

- **並び替え UI を dnd-kit ではなく ▲▼ ボタンにした**（`raw/issues/2026-07-01_11/plan.md` 参照）: 新規 npm 依存を追加せず、既存の `delete` フォームと同じ progressive enhancement パターンで実装・テストできるため。ユーザーに直接確認を取り決定した。
- **`updateTodoTitle` は他人の TODO 操作時に `{error}` を返すが、`toggleTodo`/`moveTodo` は no-op**: `updateTodoTitle` は `useActionState` でエラー表示 UI を持つため対称的にエラーを返せるが、`toggleTodo`/`moveTodo` は fire-and-forget な plain form であり `deleteTodo` の既存方針（無変更で return）を踏襲した。
- **`moveTodo` を対話的トランザクション（`prisma.$transaction(async (tx) => {...})`）にした**: 初回実装は読み取り（`findFirst`）がトランザクション外にあり、同時実行時に読み取った `position` が古くなるレースコンディションの余地があった。レビュー（review-agent）で Must 指摘を受け、読み取り〜書き込みを同一トランザクション内に統一した。
- **`position` の入れ替えを一時値 `-1` 経由の3ステップにした**: `(userId, position)` に一意制約を追加したため、2件を直接入れ替えると中間状態で一意制約に違反する。`createTodo` が常に 0 以上の連番を採番するため、`-1` は既存データと衝突しない安全な退避値として選んだ。

## 外部依存

- **DB**: SQLite（Prisma Client経由）。新規マイグレーションで `Todo` テーブルに `(userId, position)` の一意インデックスを追加。
- **認証**: 既存の `getSession()`（cookie ベースのセッション）を全 Action で再検証。
- **ライブラリ**: 新規ランタイム依存なし。テスト用に `@vitest/coverage-v8`（devDependency, バージョン固定）を追加。

## 副作用

- `updateTodoTitle` / `toggleTodo` / `moveTodo` はいずれも成功時に DB を更新し `revalidatePath('/')` を呼ぶ（`/` ページの Next.js キャッシュを無効化して再取得させる）。
- 例外発生時は `console.error('[todos] <action>Error', { userId, todoId }, e)` の形式でログを出す。タイトル本文はログに含めない（既存方針を継続）。

## コードウォークスルー

### `app/actions/todos.ts:71-114` — `updateTodoTitle`

`useActionState` にバインドされる Action。`id`/`title` を FormData から取り、既存の `TitleSchema`（`trim().min(1).max(255)`）で検証してから `updateMany({ where: { id, userId }, data: { title } } )` を実行する。`result.count === 0` は「id が存在しない」または「他人の TODO」のいずれかであり、区別せず `{ error: 'TODO が見つかりません' }` を返す。

### `app/actions/todos.ts:116-139` — `toggleTodo`

`findFirst({ id, userId })` で所有権確認を兼ねて現在の `todo` を取得し、見つかった場合のみ `completed` を反転して `update` する。他人の TODO の id を渡された場合は `todo` が `null` になり、何もせず `return` する。

### `app/actions/todos.ts:141-183` — `moveTodo`

```ts
await prisma.$transaction(async (tx) => {
  const current = await tx.todo.findFirst({ where: { id, userId: session.userId } })
  if (!current) return
  const neighborPosition = direction === 'up' ? current.position - 1 : current.position + 1
  const neighbor = await tx.todo.findFirst({ where: { userId: session.userId, position: neighborPosition } })
  if (!neighbor) return
  const tempPosition = -1
  await tx.todo.update({ where: { id: current.id }, data: { position: tempPosition } })
  await tx.todo.update({ where: { id: neighbor.id }, data: { position: current.position } })
  await tx.todo.update({ where: { id: current.id }, data: { position: neighbor.position } })
})
```

読み取り2回・書き込み3回すべてを同一の対話的トランザクション（`tx`）内で行うため、同時に2つの `moveTodo` 呼び出しが発生してもトランザクションが直列化され、`position` の整合性（ユーザー内で重複・欠番のない連番）が保たれる。

### `app/components/TodoTitleEditor.tsx:1-55`

`isEditing` state で表示⇄編集を切り替える。編集モードの `<form action={action}>` は `useActionState(updateTodoTitle, null)` にバインドされ、送信成功（`state === null` かつ送信済み）を検知したら自動的に表示モードへ戻る（`AddTodoForm.tsx` と同じ `submittedRef` パターン）。

### `app/components/TodoList.tsx:1-37`

各 TODO を `index` 付きで `map` し、先頭要素（`index === 0`）の ▲ ボタンと末尾要素（`index === todos.length - 1`）の ▼ ボタンに `disabled` を付与して誤操作を防ぐ。

## レビュー対応の記録

初回レビューで review-agent から Must 3件（`@vitest/coverage-v8` のバージョン固定、`moveTodo` の非アトミック性、`position` の DB 一意制約欠如）を受け、修正後の再レビューで codex-review / review-agent とも Approve となった。詳細は `raw/issues/2026-07-01_11/plan.md` のリスク分析および本ドキュメントの「主要な判断分岐」を参照。
