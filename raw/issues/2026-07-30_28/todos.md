# タスクリスト（Issue #28）

## 実装タスク

- [x] タスク1: Terraform に todo_migrate ユーザー・migrate 用 Secret 枠・Cloud Run Job・variables を追加（見積もり: 1.5h）
- [x] タスク2: scripts/sql/setup-db-roles.sql を作成（所有権移転 + GRANT 最小化 + DEFAULT PRIVILEGES）（見積もり: 1h）
- [x] タスク3: Dockerfile の CMD から migrate を除去し、cloudbuild.yaml に「job image 更新 → execute --wait → deploy」を挿入（見積もり: 0.5h）

## テストタスク

- [x] テスト1: scripts/sql/verify-db-roles.sh を作成し、ローカル PostgreSQL で 4 assert（migrate 成功・DDL 拒否・CRUD 成功・DEFAULT PRIVILEGES）→ 全 PASS
- [x] テスト2: terraform fmt / terraform validate の通過
- [ ] テスト3: `npm run test` / `npm run test:pg` の回帰、docker compose でのローカル起動確認（受入判定フェーズで実施）
- [x] テスト4: roles/run.developer が run.jobs 系を含むことの確認（含む見込み。人間実行時に gcloud で最終確認）

## ドキュメントタスク

- [x] `raw/` コンテキスト記録 + 人間実行手順書 → result.md（cloudsqlsuperuser 継承の実機確認を手順 5 に明記）
