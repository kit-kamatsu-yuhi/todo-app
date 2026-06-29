# タスクリスト — Issue #8 User / Todo テーブル作成

## 実装タスク
- [ ] T1: `prisma/schema.prisma` に `User` モデルを追加（id/email/passwordHash/createdAt）（見積もり: 0.5h）
- [ ] T2: `prisma/schema.prisma` に `Todo` モデルを追加（id/userId/title/completed/position/createdAt/updatedAt）（見積もり: 0.5h）
- [ ] T3: User-Todo リレーション定義（1-n、onDelete: Cascade）（見積もり: 0.25h）
- [ ] T4: `npx prisma migrate dev --name init-user-todo` でマイグレーション生成・適用（見積もり: 0.5h）
- [ ] T5: `npx prisma generate` で Prisma Client 再生成（見積もり: 0.25h）
- [ ] T6: `docker-compose.yml` に `prisma migrate deploy` を起動前コマンドとして追加（見積もり: 0.5h）
- [ ] T7: `Dockerfile` の runner ステージに `prisma/migrations/` のコピーが含まれることを確認・修正（見積もり: 0.5h）

## テストタスク
- [ ] TT1: `tests/schema.test.ts` のテスト基盤整備（テスト用 DB 設定・マイグレーション・クリーンアップ）（見積もり: 1h）
- [ ] TT2: ST1 — User 作成テスト（id/email/createdAt が返る）（見積もり: 0.25h）
- [ ] TT3: ST2 — email unique 制約テスト（同一 email で Prisma エラー）（見積もり: 0.25h）
- [ ] TT4: ST3 — Todo 作成テスト（completed が default false）（見積もり: 0.25h）
- [ ] TT5: ST4 — 存在しない userId で Todo 作成 → FK 制約エラー（見積もり: 0.25h）
- [ ] TT6: ST5 — User 削除で関連 Todo が Cascade 削除される（見積もり: 0.25h）
- [ ] TT7: 手動: `docker compose up` → `GET /api/health` が 200（migrate deploy が実行され起動できること）

## ドキュメントタスク
- [ ] D1: `raw/issues/2026-06-29_8/` にコンテキスト記録（changes.md は /create-pr で生成）

## 依存関係
- T1 → T2 → T3（スキーマ定義は順に）
- T3 → T4 → T5
- T4 → T6, T7（マイグレーション生成後に Docker 設定を確定）
- T5 → TT1（Prisma Client 再生成後にテスト実装）
- TT1 → TT2〜TT6
- TT2〜TT6 → TT7（手動）
