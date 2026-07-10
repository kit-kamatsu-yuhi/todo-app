# todo-app

Next.js (App Router) + React + Prisma + PostgreSQL の Todo アプリ。

## 技術スタック

- TypeScript / React 19 / Next.js 15 (App Router, Node ランタイム)
- Prisma + PostgreSQL
- テスト: Vitest + Testing Library
- Lint / Format: ESLint + Prettier
- Docker / Docker Compose

## ディレクトリ構成

```
app/
  layout.tsx              共通レイアウト
  page.tsx                トップページ
  api/health/route.ts     GET /api/health（DB 接続確認つき）
lib/prisma.ts             PrismaClient シングルトン
prisma/schema.prisma      datasource(postgresql) + generator + モデル定義
tests/                    Vitest テスト
Dockerfile                multi-stage（standalone 出力）
docker-compose.yml        app + db(PostgreSQL) + named volume postgres-data
```

## Docker で起動する

ローカルに Node がなくても起動できる。

```bash
docker compose up --build
```

起動後、ブラウザで http://localhost:3000 を開くとトップページが表示される。
ヘルスチェックは以下で確認する。

```bash
curl http://localhost:3000/api/health
# => {"status":"ok","db":"ok"}
```

PostgreSQL のデータは named volume `postgres-data`（コンテナ内 `/var/lib/postgresql/data`）に保存される。`docker compose restart` や `docker compose down`（`-v` なし）→ `up` をしてもデータは保持される。`app` は `db` の healthcheck 通過後に起動し、`prisma migrate deploy` でスキーマを適用してから本体を立ち上げる。

停止する。

```bash
docker compose down
```

ボリュームごと破棄する場合は `docker compose down -v` を使う。

## ローカルで開発する

```bash
npm install          # postinstall で prisma generate が走る
npm run dev          # http://localhost:3000
```

ローカル実行時の `DATABASE_URL` は `.env` で定義する（`.env.example` をコピーして利用する）。

```bash
cp .env.example .env
```

`.env` の既定値は `postgresql://todo:todo@localhost:5432/todo?schema=public` で、docker-compose の `db` サービス（`docker compose up db`）に接続する。別の PostgreSQL を使う場合は接続文字列を書き換える。マイグレーション適用は `npx prisma migrate deploy`（本番相当）または `npx prisma migrate dev`（開発）で行う。

## テスト

```bash
npm run test:pg      # テスト用 PostgreSQL コンテナ起動 → migrate deploy → vitest run → 後始末
```

`scripts/test-with-postgres.sh` は `postgres:16-alpine` の一時コンテナを起動し、`TEST_DATABASE_URL=postgresql://todo:todo@localhost:15432/todo_test?schema=public` を設定してから Vitest を実行する（既定ポート 15432 は開発 DB の 5432 と衝突しない）。ポートを変える場合は `TEST_DB_PORT=25432 npm run test:pg` のように指定する。

> **注意**: PostgreSQL 移行に伴い、テストは稼働中の PostgreSQL が前提になる（`npm test` 単体は DB が無いと失敗する）。CI で実行する場合は PostgreSQL サービスを起動し `TEST_DATABASE_URL`（DB 名は `*_test`）を渡して `npm test` を呼ぶこと（`.github/workflows/test.yml` 参照）。破壊的操作の誤爆防止として、DB 名が `_test` で終わらない場合はセットアップが停止する（`ALLOW_NON_TEST_DATABASE=1` で解除）。

既存の PostgreSQL を使う場合は、テスト用 DB を用意して `TEST_DATABASE_URL` を指定する。

```bash
createdb -O todo todo_test
export TEST_DATABASE_URL="postgresql://todo:todo@localhost:5432/todo_test?schema=public"
npm test             # globalSetup が prisma migrate deploy を実行する
```

docker compose の `db` サービスを使う場合。

```bash
docker compose up -d db
docker compose exec db createdb -U todo todo_test
TEST_DATABASE_URL="postgresql://todo:todo@localhost:5432/todo_test?schema=public" npm test
```

- `tests/health.test.ts`: `/api/health` の GET が 200 / `status: ok` を返す（Prisma はモック）
- `tests/page.test.tsx`: トップページが「todo-app」見出しを render する

## Lint / Format

```bash
npm run lint         # next lint (ESLint)
npm run format       # prettier --write
npm run format:check # prettier --check
```

## ビルド

```bash
npm run build        # prisma generate + next build
npm start            # 本番起動
```
