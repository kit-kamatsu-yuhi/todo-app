# Issue #9: メールアドレスログイン — 実装変更解説

- date: 2026-06-30
- branch: feature/9-email-auth
- commit: 1c7d203

## 概要

email + password によるサインアップ / ログイン / ログアウトを Next.js App Router (Server Actions) で実装した。パスワードは bcryptjs でハッシュ化し、セッションは Prisma Session テーブル + HttpOnly Cookie で管理する。

## アーキテクチャ変更フロー

```mermaid
flowchart TD
    subgraph Browser
        A[フォーム送信]
    end

    subgraph ServerActions["Server Actions (app/actions/auth.ts)"]
        B[zod バリデーション]
        C{処理分岐}
        D[hashPassword]
        E[verifyPassword + DUMMY_HASH]
        F[prisma.user.create]
        G[prisma.user.findUnique]
        H[createSession]
        I[deleteSession]
    end

    subgraph AuthLib["認証ライブラリ (lib/auth/)"]
        J[password.ts: bcrypt cost=12]
        K[session.ts: Session DB + Cookie]
    end

    subgraph DB["Prisma / SQLite"]
        L[(User テーブル)]
        M[(Session テーブル)]
    end

    subgraph Middleware["middleware.ts"]
        N{Cookie 'session' 存在?}
        O[通過]
        P[/login へリダイレクト]
    end

    A -->|signup| B
    A -->|login| B
    A -->|logout| I
    B --> C
    C -->|signup| D --> F --> H
    C -->|login| G --> E --> H
    H --> K --> M
    F --> L
    K -->|Set-Cookie| Browser

    N -->|あり| O
    N -->|なし| P
```

## ファイル別変更

### 新規ファイル

| ファイル | 役割 |
|---------|------|
| `lib/auth/password.ts` | `hashPassword` / `verifyPassword`（bcryptjs wrapper） |
| `lib/auth/session.ts` | Session DB 操作 + Next.js Cookie 統合 |
| `app/actions/auth.ts` | `signup` / `login` / `logout` Server Actions |
| `app/signup/page.tsx` | サインアップフォーム（useActionState） |
| `app/login/page.tsx` | ログインフォーム（useActionState） |
| `middleware.ts` | Cookie 存在確認によるルートガード |
| `prisma/migrations/20260630003451_add_session/migration.sql` | Session テーブル作成 |
| `tests/auth/password.test.ts` | password 関数の Unit テスト（4件） |
| `tests/auth/session.test.ts` | Session DB 操作の Integration テスト（6件） |
| `tests/auth/actions.test.ts` | Server Actions の Integration テスト（9件） |

### 変更ファイル

| ファイル | 変更内容 |
|---------|---------|
| `prisma/schema.prisma` | Session モデル追加、User に sessions リレーション追加 |
| `tests/helpers/db.ts` | `cleanDb()` に `session.deleteMany()` を追加 |
| `package.json` | bcryptjs, zod, @types/bcryptjs を追加（バージョン固定） |
| `vitest.config.ts` | `hookTimeout: 60000`, `testTimeout: 15000` に延長 |

## セキュリティ設計のポイント

### Timing Attack 対策

ユーザーが存在しない場合も `verifyPassword` をダミーハッシュで実行し、応答時間を一定に保つ。

```typescript
// ユーザー不在でも bcrypt.compare を実行する
const valid = await verifyPassword(password, user?.passwordHash ?? DUMMY_HASH)
if (!user || !valid) {
  return { error: 'メールアドレスまたはパスワードが正しくありません' }
}
```

### TOCTOU 対策

重複 email チェックを `findUnique + create` の 2ステップで行わず、`create` の P2002 エラーを直接捕捉する。

```typescript
try {
  const user = await prisma.user.create({ data: { email, passwordHash } })
  await createSession(user.id)
} catch (e) {
  if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
    return { error: 'このメールアドレスはすでに登録されています' }
  }
  throw e
}
```

### middleware の設計

Edge Runtime では Prisma が使えないため、middleware は Cookie の**存在確認のみ**行う。セッション有効期限の検証は `getSession()` を呼ぶ Server Component 側で行う。

## テスト設計

`singleFork: true`（DB 競合防止）+ bcrypt cost=12（~1.5秒/回）のため `hookTimeout: 60000` / `testTimeout: 15000` に延長した。
