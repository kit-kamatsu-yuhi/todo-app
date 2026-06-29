# Issue #7: HTMX + Hono.js + SQLite 環境構築（Docker 定義）

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/7
- labels: chore, priority:high, size:M
- 依存: なし（後続の User/Todo テーブル作成 ほかを Blocks）

## 概要
HTMX + Hono.js(TypeScript) + SQLite で動く todo-app の開発環境を Docker で定義し、最小構成のアプリが起動・テストできる状態にする。

## 受け入れ条件
- Given クリーンな環境 / When `docker compose up` / Then アプリ起動・`GET /health` が 200
- Given コンテナ再起動 / When SQLite を参照 / Then データ保持
- Given `npm test` / When 実行 / Then サンプルテスト green
- Given トップページ / When アクセス / Then HTMX を含むページ表示

## 設計メモ
- 構成: docker-compose（app + SQLite 永続ボリューム）
- ディレクトリ案: `src/`, `src/views/`, `migrations/`, `tests/`
- エンドポイント: `GET /health`（200）, `GET /`（HTMX 最小ページ）

## 技術スタック
HTMX + Hono.js(TypeScript) + SQLite、Docker で環境定義。テストは vitest 想定、lint/format 導入。
