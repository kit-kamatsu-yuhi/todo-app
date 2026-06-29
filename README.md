# todo-app

Next.js (App Router) + React + Prisma + SQLite の Todo アプリ。本リポジトリは環境構築（Issue #7）の scaffolding を含む。業務モデルとマイグレーションは Issue #8 以降で追加する。

## 技術スタック

- TypeScript / React 19 / Next.js 15 (App Router, Node ランタイム)
- Prisma + SQLite
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
prisma/schema.prisma      datasource(sqlite) + generator のみ
tests/                    Vitest テスト
Dockerfile                multi-stage（standalone 出力）
docker-compose.yml        app + named volume db-data
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

SQLite の DB ファイルは named volume `db-data`（コンテナ内 `/app/data/dev.db`）に保存される。`docker compose restart` や `docker compose down`（`-v` なし）→ `up` をしてもデータは保持される。

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

`.env` の既定値は `file:/app/data/dev.db` で Docker 向け。ローカルでファイルパスを変えたい場合は `DATABASE_URL="file:./prisma/dev.db"` 等に書き換える。

## テスト

```bash
npm test             # vitest run（watch しない）
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
