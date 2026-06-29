# Issue #7 環境構築（env-setup）

- date: 2026-06-29
- topic: Next.js App Router + SQLite + Prisma + Docker + vitest による開発環境構築

## 実施内容

Issue #7 で要求された基本開発環境を構築した。

- Next.js 15 App Router プロジェクトの初期化
- Prisma + SQLite によるデータ永続化層の設定
- Docker / docker-compose によるコンテナ実行環境の構築
- vitest + @testing-library/react によるテスト基盤の整備
- GET /api/health エンドポイントの実装（DB 疎通確認用）

## 決定事項

### 技術選定の根拠

- Next.js App Router: サーバーコンポーネントとルートハンドラを使いたいため採用。Pages Router は避けた
- SQLite: 開発初期フェーズでは RDS/Cloud SQL などの外部 DB を不要にしたい。Docker volume にファイルを置くことで docker compose up のみで完結する
- Prisma: TypeScript との型統合が良く、スキーマ定義から Client 自動生成できる。SQLite ドライバーの取り扱いも安定している
- vitest: Vite と統合できるため設定が少ない。Jest との互換 API で既存の知識が活用できる

### Node ランタイム選択の理由（Edge 不可）

`/api/health` ルートは `prisma.$queryRaw` を呼ぶため Edge Runtime では動作しない。`export const runtime = "nodejs"` を明示して Node.js ランタイムを強制した。Edge Runtime は Prisma Client を読み込めないため、DB アクセスが必要なルートハンドラには Node ランタイムが必要。

### Docker での Prisma CLI 不使用にした理由

現時点ではモデルが存在しない（スキーマは空のまま）。`prisma migrate deploy` を実行してもマイグレーションファイルがなく意味がないため、Dockerfile の起動コマンドには含めなかった。Issue #8 でモデルを追加した際に `migrate deploy` を追加する予定。

## 現在のプロジェクト状態

- `npm test` で 2 テストが pass（DB 成功パス + DB 失敗パス）
- `docker compose up` で http://localhost:3000 にアクセス可能な状態
- `GET /api/health` が 200 `{ status: "ok", db: "ok" }` を返す（SQLite への SELECT 1 が通ること）

## 未解決事項 / 既知の判断事項

- `npm audit` の moderate 1件（依存パッケージ起因）は許容済み。直接の脆弱性ではなく、修正版への更新が現時点でできないため様子見とする
- Prisma の `migrate deploy` は Issue #8 でモデル追加時に組み込む
