# タスクリスト（Issue #28）

## 実装タスク

- [ ] タスク1: Terraform に todo_migrate ユーザー・migrate 用 Secret 枠・Cloud Run Job・variables を追加（見積もり: 1.5h）
- [ ] タスク2: scripts/sql/setup-db-roles.sql を作成（所有権移転 + GRANT 最小化 + DEFAULT PRIVILEGES）（見積もり: 1h）
- [ ] タスク3: Dockerfile の CMD から migrate を除去し、cloudbuild.yaml に「job image 更新 → execute --wait → deploy」を挿入（見積もり: 0.5h）

## テストタスク

- [ ] テスト1: scripts/sql/verify-db-roles.sh を作成し、ローカル PostgreSQL で (a) todo_migrate の migrate 成功 (b) todo_app の DDL 拒否 (c) todo_app の CRUD 成功 (d) 新テーブルへの DEFAULT PRIVILEGES 適用を assert
- [ ] テスト2: terraform fmt / terraform validate の通過
- [ ] テスト3: `npm run test` / `npm run test:pg` の回帰、docker compose でのローカル起動確認
- [ ] テスト4: roles/run.developer が run.jobs.update / run.jobs.run を含むことの確認

## ドキュメントタスク

- [ ] `raw/` コンテキスト記録 + 人間実行手順書（terraform apply → Secret 投入 → SQL 投入 → cd-* タグ push の順序と確認事項）
