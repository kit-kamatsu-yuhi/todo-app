# Issue #9: メールアドレスログイン実装

- date: 2026-06-30
- topic: email/password 認証（signup / login / logout）+ Cookie セッション

## 実施内容

- Prisma Session モデル追加（`add_session` マイグレーション）
- `lib/auth/password.ts` — bcryptjs (cost=12) によるパスワードハッシュ
- `lib/auth/session.ts` — Session DB 操作 + Next.js Cookie 統合（HttpOnly / SameSite=lax）
- `app/actions/auth.ts` — signup / login / logout Server Actions
- `app/signup/page.tsx`, `app/login/page.tsx` — フォーム（useActionState）
- `middleware.ts` — Cookie 存在確認によるルートガード
- 27 テスト全通過（Unit 4件 + Integration 22件 + 既存 8件）

## 決定事項

### middleware の設計

Edge Runtime では Prisma が利用不可。middleware は Cookie の存在確認のみを行い、セッション有効期限の検証は `getSession()` を呼ぶ Server Component 側に委ねる。

### Timing Attack 対策

ユーザーが存在しない場合も `verifyPassword(password, DUMMY_HASH)` を実行して応答時間を均一化した。DUMMY_HASH は事前計算済みの bcrypt ハッシュ。

### TOCTOU 対策

`findUnique` + `create` の 2ステップを廃止し、`create` の Prisma P2002（ユニーク制約違反）エラーを直接捕捉する方式に変更。

### テストタイムアウト延長

bcrypt cost=12 は 1回 ~1.5 秒かかる。また Prisma binary の cold start が初回 ~18 秒かかることから、`hookTimeout: 60000` / `testTimeout: 15000` に延長した。

### check-secrets.sh の修正

`passwordHash = await hashPassword(...)` がシークレット検出の正規表現に誤検知されたため、関数呼び出し代入を除外するようパターンを修正した。

## 現在のプロジェクト状態

- feature/9-email-auth ブランチ：PR 作成待ち
- 認証の土台が完成。次の Issue #10（JWT / Todo CRUD）は getSession() を呼んで認証済みユーザーを取得可能

## 未解決事項

- middleware はセッション有効期限を検証しない（Cookie 存在確認のみ）。期限切れセッションが 7 日間の Cookie TTL を超えると自動で排除されるが、セッション強制失効（ログアウト後の既存 Cookie 再利用防止）は Server Component 側の責務
- 期限切れセッションの定期削除 Job が未実装（今後の Issue で対応予定）
