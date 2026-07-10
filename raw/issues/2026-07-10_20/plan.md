# 実装計画: Issue #20 TODO アプリの DB を PostgreSQL へ移行

対象 Issue: https://github.com/kit-kamatsu-yuhi/todo-app/issues/20
worktree: `.claude/worktrees/20-prisma-postgres`（branch `feature/20-prisma-postgres`）

## 1. 要件分析

**機能要件**
- Prisma datasource provider を `sqlite` → `postgresql` に変更する
- 接続は `DATABASE_URL`（`postgresql://...`）から取得する（コード/.env に機密を置かない）
- 既存機能（認証・セッション・Todo・カテゴリ・並び替え）を PostgreSQL 上で維持する
- ローカル開発用に docker-compose へ PostgreSQL サービスを追加する

**非機能要件**
- 接続文字列をリポジトリにコミットしない
- テスト（Vitest）がグリーンを維持する

**受入基準（分類）**
- 自動テスト: 全モデルの CRUD・認証・並び替えが PostgreSQL で green
- 統合/手動: `/api/health` が `db:ok`、`docker compose up` でアプリが起動し操作できる
- E2E（任意）: ログイン → Todo 作成/並び替え/カテゴリ付与が PostgreSQL で動く

## 2. UML（Mermaid）

エンティティ関係（モデル定義は不変。provider のみ変更）。

```mermaid
erDiagram
  User ||--o{ Session : has
  User ||--o{ Todo : owns
  User ||--o{ TodoCategory : owns
  TodoCategory |o--o{ Todo : categorizes
  User { string id PK }
  Session { string id PK }
  Todo { string id PK; int position }
  TodoCategory { string id PK }
```

## 3. API 設計

変更なし。既存の Server Actions / `/api/health` はそのまま。DB プロバイダの差し替えのみ。

## 4. DB 設計

- provider `postgresql`。型マッピングは Prisma が吸収（String→text, DateTime→timestamp(3), Boolean→boolean, Int→integer, cuid→text）。
- 制約は現行維持: `@@unique([userId, position])`、`@@index([userId])`、`@@index([categoryId])`。
- **移行方法**: 既存の SQLite マイグレーション（`prisma/migrations/*`）は provider 依存のため破棄し、PostgreSQL 向けに init マイグレーションを再生成する（`prisma migrate reset` → `migrate dev`）。開発 DB のみのため既存データ消失は許容。
- **注意（リスク→§10）**: `@@unique([userId, position])` は PostgreSQL でも即時評価。並び替えのバルク更新で一時的な重複が起きると制約違反になり得る。

## 5. フロントエンド設計

N/A（UI 変更なし）。

## 6. セキュリティ基準

- `DATABASE_URL`（接続文字列）は機密。`.env.example` はプレースホルダのみ、実値はコミットしない。本番は Secret Manager 注入（#21）。
- ログに接続文字列・パスワードを出さない（既存 `/api/health` の方針を踏襲）。

## 7. ロギング要件

- 接続エラーは概要のみ記録（機密マスキング）。新規ログ要件なし。

## 8. テスト戦略

- `tests/helpers/db.ts` の SQLite ファイル接続（`prisma/test.db`）を PostgreSQL 接続に変更する。
- テスト用 DB は docker-compose の `db` サービス（`localhost:5432` / 専用 DB `todo_test`）。`TEST_DATABASE_URL` で上書き可能に。
- 各テスト前に `migrate deploy`（初回）+ `cleanDb()`。`vitest.config.ts` の直列実行方針は維持。
- ローカル/CI とも PostgreSQL 起動が前提になる点を README に明記。
- カバレッジは現状維持（80% 目安）。

## 9. タスク分解

`todos.md` 参照（1 タスク ≤2h に分解）。

## 10. リスク分析と対策

| リスク | 影響 | 対策 |
|--------|------|------|
| 並び替えの `@@unique([userId,position])` 制約違反（Postgres 即時評価） | 中 | 並び替えをトランザクション内で一時オフセット退避 or 検証テスト追加。既存ロジックを Postgres で回帰確認 |
| テストが PostgreSQL 必須になりローカル/CI に依存追加 | 中 | docker-compose `db` サービス提供 + README 手順化。CI は将来 postgres service |
| `prisma migrate reset` による開発 DB データ消失 | 低 | 開発 DB のみ。本番は #21 の Cloud SQL |
| Prisma binary cold start（初回遅延） | 低 | 既存の hookTimeout 設定を踏襲 |

## 実行フロー

1. ✅ `/plan-issue` — 計画策定（完了）
2. ⬜ ユーザー承認 — plan.md + todos.md の確認
3. ⬜ `/codex-team all` — 実装/テスト/レビュー（codex sub-agent チーム）
4. ⬜ `/create-pr` — PR 作成（/walkthrough → changes.md → PR）
