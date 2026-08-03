# Issue #28: DB ユーザーの権限分離（app / migration）と GRANT 最小化

- date: 2026-07-30
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/28
- labels: feat, priority:high, size:L
- 出典: Week 11 セキュリティ監査（raw/conversations/2026-07-30_week11-security-audit.md）

## 背景

DB ユーザーは `todo_app` 1 つ（terraform/database.tf）。`Dockerfile:53` の CMD が起動時に同一ユーザーで `prisma migrate deploy`（DDL）を実行しており、アプリの実行権限でスキーマ変更が可能な状態。GRANT 文はリポジトリに存在しない。

## 設計メモ

- `todo_migrate`（スキーマ所有者・DDL）と `todo_app`（DML のみ）に分離。`ALTER DEFAULT PRIVILEGES` で migration が作る新規テーブルにも todo_app の DML 権限を自動付与する
- migrate 実行は Dockerfile CMD から外し、Cloud Build のデプロイステップまたは Cloud Run Job へ移す
- DATABASE_URL は app 用 / migrate 用の 2 本を Secret Manager 管理。Terraform に `google_sql_user` と Secret を追加
- 検証: `todo_app` で `CREATE TABLE` が権限エラーになること
- 関連: #21（インフラ構築）、#22（デプロイ調整）
