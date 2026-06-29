# タスクリスト — Issue #7 環境構築

## 実装タスク
- [ ] T1: Next.js(TypeScript, App Router) プロジェクト初期化（package.json / tsconfig / next.config）（見積もり: 1h）
- [ ] T2: ESLint / Prettier 設定（見積もり: 0.5h）
- [ ] T3: `app/layout.tsx` + `app/page.tsx`（React 最小ページ）（見積もり: 0.5h）
- [ ] T4: `app/api/health/route.ts`（`runtime='nodejs'`, 200 + DB 接続確認）（見積もり: 0.5h）
- [ ] T5: Prisma 導入・`prisma/schema.prisma`（sqlite datasource + generator のみ、モデルは #8）（見積もり: 0.75h）
- [ ] T6: `lib/prisma.ts`（PrismaClient シングルトン）（見積もり: 0.5h）
- [ ] T7: `prisma generate` + 初回接続で DB ファイル作成確認（マイグレーションは #8）（見積もり: 0.5h）
- [ ] T8: `Dockerfile`（multi-stage, Node runtime）+ `.dockerignore`（見積もり: 1h）
- [ ] T9: `docker-compose.yml`（app + named volume `db-data` を `/app/data` に、起動前 `migrate deploy`）（見積もり: 1h）
- [ ] T10: `.env.example`（`DATABASE_URL=file:/app/data/dev.db`）（見積もり: 0.25h）

## テストタスク
- [ ] TT1: vitest 基盤導入（設定・scripts）（見積もり: 0.5h）
- [ ] TT2: `tests/health.test.ts` — `/api/health` が 200 / `status: ok`（見積もり: 0.5h）
- [ ] TT3: `tests/page.test.tsx` — トップページが見出しを render（見積もり: 0.5h）
- [ ] TT4: 手動: `docker compose up` 起動・`GET /api/health` 200 確認
- [ ] TT5: 手動: コンテナ再起動後も DB ファイルがボリュームに残り `/api/health` が db:ok（テーブル round-trip は #8）

## ドキュメントタスク
- [ ] D1: README に起動・テスト手順を記載
- [ ] D2: `raw/issues/2026-06-29_7/` にコンテキスト記録（changes.md は /walkthrough で生成）

## 依存関係
- T1 → (T2, T3, T4, T5)
- T5 → T6 → T7
- T4 は T6（prisma client）に依存（DB 接続確認のため）
- (T1〜T7) → T8 → T9
- 実装一式 → TT1〜TT3 → TT4, TT5（手動）
