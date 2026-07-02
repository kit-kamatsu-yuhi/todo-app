# Issue #12: TODO カテゴリ機能 — 実装解説

- date: 2026-07-02
- branch: `feature/12-todo-category`
- base: `main`（merge-base: `c455ad7`）

## 概要

TODO をカテゴリで分類できるようにする。`TodoCategory` モデルを追加し、カテゴリの作成・削除、TODO への割り当て・解除、カテゴリによる一覧の絞り込みを実装した。

## 変更ファイル

| ファイル | 種別 | 内容 |
|---|---|---|
| `prisma/schema.prisma` | DB | `TodoCategory` モデル追加、`Todo.categoryId`（nullable, `onDelete: SetNull`）追加 |
| `prisma/migrations/20260702022804_add_todo_category/` | DB | 上記マイグレーション |
| `app/actions/categories.ts` | 新規 | `createCategory` / `deleteCategory` |
| `app/actions/todos.ts` | 実装 | `assignCategory` を追加（Todo・Category両方の所有権確認をトランザクション内で実施） |
| `app/components/AddCategoryForm.tsx` | 新規 | カテゴリ作成フォーム（Client Component） |
| `app/components/CategoryList.tsx` | 新規 | 絞り込みGETフォーム + カテゴリ一覧・削除（Server Component） |
| `app/components/TodoList.tsx` | 実装 | `categories` props 追加、カテゴリ割り当て用 select を追加 |
| `app/page.tsx` | 実装 | `searchParams` 対応、`categoryId` 絞り込み、todos/categories 並列取得 |
| `tests/categories/*`, `tests/todos/actions.test.ts`, `tests/schema.test.ts`, `tests/page.test.tsx`, `tests/todos/TodoList.test.tsx` | テスト | 新規・拡張 |

## アーキテクチャ概要

`app/page.tsx` が `searchParams.category` を読み取り、`prisma.todo.findMany`（`categoryId` 条件付き）と `prisma.todoCategory.findMany` を並列取得する。`AddCategoryForm`（カテゴリ作成）、`CategoryList`（絞り込み + カテゴリ削除）、`TodoList`（カテゴリ割り当て）の3コンポーネントに機能を分割し、いずれも plain form + Server Actions で実装した。絞り込みは Server Action を使わず `<form method="get">` によるブラウザのネイティブ GET 遷移で実現しており、JS が無効でも動作する。

## 処理フロー

```mermaid
flowchart TD
    A[ユーザー操作] --> B{操作の種類}

    B -->|カテゴリ作成| C[AddCategoryForm: 名前入力→送信]
    C --> D[createCategory]
    D --> E{getSession}
    E -->|null| F[エラー: ログインが必要です]
    E -->|OK| G{NameSchema検証}
    G -->|空/空白/50文字超| H[エラー表示]
    G -->|OK| I["todoCategory.create userId,name"]
    I --> J[revalidatePath→一覧・selectに反映]

    B -->|カテゴリ削除| K[form action=deleteCategory]
    K --> L{getSession}
    L -->|null| M[/loginへredirect]
    L -->|OK| N["todoCategory.deleteMany id,userId"]
    N --> O["DB FK制約 onDelete:SetNull で紐づくTodo.categoryIdが自動でnullになる"]
    O --> J

    B -->|カテゴリ割り当て/解除| P[TodoListのselect→変更ボタン]
    P --> Q[assignCategory]
    Q --> R{getSession}
    R -->|null| M
    R -->|OK| S[対話的トランザクション開始]
    S --> T{categoryId空文字?}
    T -->|Noカテゴリ指定あり| U["tx.todoCategory.findFirst id,userId"]
    U -->|null: 他人のカテゴリ| V[no-op トランザクション内return]
    U -->|取得| W["tx.todo.updateMany id,userId categoryId"]
    T -->|Yes未分類| W
    W --> J

    B -->|カテゴリで絞り込み| X[CategoryListのGETフォーム→送信]
    X --> Y["/?category=idへブラウザ遷移"]
    Y --> Z["page.tsx: todo.findMany where userId AND categoryId"]
```

詳細な判断分岐は下記「主要な判断分岐」を参照。

## エントリーポイント

- 一覧描画: `app/page.tsx:10-45`（`searchParams` を受け取り `todo.findMany`/`todoCategory.findMany` を並列実行）
- カテゴリ作成: `app/components/AddCategoryForm.tsx:6-32`
- カテゴリ絞り込み・削除: `app/components/CategoryList.tsx:4-41`
- カテゴリ割り当て: `app/components/TodoList.tsx:29-40`

## データフロー

1. `page.tsx` が `searchParams.category`（あれば）を読み取り、`userId` 条件と組み合わせた `where` で `todo.findMany` を実行する。
2. 同時に `todoCategory.findMany({ where: { userId } })` でログインユーザーの全カテゴリを取得し、`AddCategoryForm` 以外の3コンポーネント（`CategoryList`、`TodoList` の select）にすべて同じ `categories` を渡す。
3. カテゴリ作成・削除・割り当てはいずれも成功時に `revalidatePath('/')` を呼び、`page.tsx` を再実行してキャッシュを更新する。
4. 絞り込みは Server Action を経由せず、`<form method="get">` によるブラウザのネイティブ遷移で `/?category=<id>` に移動し、`page.tsx` が新しい `searchParams` で再描画される。

## 主要な判断分岐

- **絞り込みを Server Action ではなく GET フォームにした**: query param（`?category=<id>`）が状態のソースオブトゥルースになり、JS なしでも動作する。既存の progressive enhancement 方針と一貫する。
- **カテゴリ削除時の `Todo.categoryId` null 化を DB の `onDelete: SetNull` に委ねた**（`app/actions/categories.ts:57-58`）: アプリケーションコード側で個別に `updateMany` する実装も検討したが、DB の FK 制約に一本化することでロジックが単純になり、`tests/schema.test.ts` で DB レベルの動作を直接検証できる。レビューで「将来的に別DBへ移行した場合のリスク」を指摘されたが、plan.md 記載の意図的な判断として維持し、コードにその旨のコメントを追加した
- **`assignCategory` は Todo・Category 双方の所有権を確認する**（`app/actions/todos.ts:196-210`）: 初回実装ではカテゴリの所有権確認（`findFirst`）と Todo の更新（`updateMany`）が別クエリだったため、review-agent の指摘を受け `prisma.$transaction(async (tx) => {...})` に変更し、Issue #11 の `moveTodo` と同じパターンでアトミック化した
- **カテゴリ名に一意制約を付けない**: Issue の要件に明記がなく、同名カテゴリの禁止は範囲外と判断した。スキーマにその旨のコメントを残した
- **`Home` の `searchParams` は非同期 optional プロパティとして受け取る**（`app/page.tsx:10-14`）: 初回実装で引数全体にデフォルト値 `= {}` を与え optional にしたところ、Next.js 15 が生成する `PageProps` 制約を満たせず `next build` が失敗した。引数自体は必須のまま `searchParams` プロパティのみ optional にすることで解消した（`tsc --noEmit` では検出できず、`next build` を実際に実行して初めて判明した）

## 外部依存

- **DB**: SQLite（Prisma Client経由）。新規マイグレーションで `TodoCategory` テーブルと `Todo.categoryId` カラムを追加。
- **認証**: 既存の `getSession()` を全 Action で再検証。
- **ライブラリ**: 新規ランタイム依存なし。

## 副作用

- `createCategory` / `deleteCategory` / `assignCategory` はいずれも成功時に DB を更新し `revalidatePath('/')` を呼ぶ。
- `deleteCategory` は DB の FK 制約により、紐づく `Todo.categoryId` を副次的に null 化する（アプリケーションコードには表れない副作用）。
- 例外発生時は `console.error('[categories] <action> error', { userId }, e)` の形式でログを出す。カテゴリ名はログに含めない。

## コードウォークスルー

### `app/actions/categories.ts:13-46` — `createCategory`

`NameSchema`（`trim().min(1).max(50)`）で検証後、`todoCategory.create({ data: { userId, name } })` を実行する。既存の `createTodo` と同じエラー分岐（空/空白 vs 文字数超過でメッセージを出し分け）を踏襲している。

### `app/actions/categories.ts:48-66` — `deleteCategory`

```ts
await prisma.todoCategory.deleteMany({ where: { id, userId: session.userId } })
```
所有者チェックのみで、紐づく Todo への処理は一切書かれていない。`Todo.category` リレーションの `onDelete: SetNull`（`prisma/schema.prisma:42`）が、削除時に紐づく `Todo.categoryId` を自動で null にする。

### `app/actions/todos.ts:185-218` — `assignCategory`

```ts
await prisma.$transaction(async (tx) => {
  if (rawCategoryId !== '') {
    const category = await tx.todoCategory.findFirst({ where: { id: rawCategoryId, userId: session.userId } })
    if (!category) return
  }
  await tx.todo.updateMany({ where: { id, userId: session.userId }, data: { categoryId: rawCategoryId || null } })
})
```
カテゴリの所有権確認と Todo の更新が同一トランザクション内で行われるため、確認から更新までの間に対象カテゴリが削除される、といった競合が起きても整合性が保たれる。

### `app/page.tsx:10-31`

```ts
export default async function Home({ searchParams }: { searchParams?: Promise<{ category?: string }> }) {
  const session = await getSession()
  if (!session) redirect('/login')
  const params = await searchParams
  const [todos, categories] = await Promise.all([
    prisma.todo.findMany({
      where: { userId: session.userId, ...(params?.category ? { categoryId: params.category } : {}) },
      orderBy: { position: 'asc' },
    }),
    prisma.todoCategory.findMany({ where: { userId: session.userId }, orderBy: { createdAt: 'asc' } }),
  ])
  ...
}
```
絞り込み条件は常に `userId` とのAND条件になるため、URLに他人の categoryId を指定しても自分のTODO以外は返らない。

### `app/components/CategoryList.tsx:11-23`

```tsx
<form method="get">
  <select name="category" defaultValue={currentCategoryId ?? ''}>
    <option value="">すべて</option>
    {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
  </select>
  <button type="submit">絞り込む</button>
</form>
```
Server Action を使わない素の GET フォーム。ブラウザが `/?category=<id>` へのナビゲーションとして処理するため、JavaScript が無効でも動作する。

## レビュー対応の記録

初回レビューで codex-review から Must 1件（`app/page.tsx` の `Home` 引数のデフォルト値により `next build` が型エラーになる）、review-agent から Should 1件（`assignCategory` の TOCTOU）を受け、それぞれ修正した。再レビューで codex-review / review-agent とも Approve となった。
