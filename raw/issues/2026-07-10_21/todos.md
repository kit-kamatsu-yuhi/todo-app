# タスクリスト: Issue #21 GCP インフラ拡張（Secret + 公開 Cloud Run + Cloud Build）

## 実装タスク
- [ ] `network.tf`: VPC Access コネクタと `connector_cidr` を削除。Direct VPC egress 用 subnet を用意（bastion subnet を流用/リネーム）。PSA 維持（見積: 1h）
- [ ] `compute.tf`: Cloud Run を Direct VPC egress に変更、image プレースホルダ + `ignore_changes`、`allUsers` 公開、`DATABASE_URL` を Secret から注入、起動コマンドで migrate deploy。bastion 削除（見積: 1.5h）
- [ ] `database.tf`: `random_password`/`secret_version` 廃止。`google_sql_user.password_wo`（未コミット tfvar）。Secret `todo-database-url` の枠のみ定義（見積: 1h）
- [ ] `iam.tf`: run SA 権限整理、bastion SA/IAP 削除、Cloud Build SA 追加（run.admin / artifactregistry.writer / iam.serviceAccountUser / logging.logWriter）（見積: 1h）
- [ ] `registry.tf`（新規）: Artifact Registry（Docker）（見積: 0.5h）
- [ ] `cloudbuild.tf`（新規）: `ci-*`/`cd-*` トリガー（GitHub 2nd-gen connection 参照）（見積: 1h）
- [ ] `cloudbuild.yaml`（新規）: build → push AR → deploy Cloud Run（見積: 1h）
- [ ] `services.tf`: cloudbuild/artifactregistry API 追加、vpcaccess 削除（見積: 0.25h）
- [ ] `scripts/connect-db.sh` 削除、変数/outputs 整理（見積: 0.5h）

## テスト/検証タスク
- [ ] `terraform fmt` / `validate` / `plan`（apply は #22）（見積: 0.5h）
- [ ] gcp-infra-review-agent でセキュリティ/コスト/正確性レビュー（見積: 0.5h）

## ドキュメント/手動手順タスク
- [ ] README に「Cloud Build GitHub 連携（手動 console 手順）」「Secret 値 GUI 投入」「apply 順序」を追記
- [ ] `raw/issues/2026-07-10_21/` に plan/todos/changes を記録

## 受け入れ条件チェック
- [ ] `terraform plan` が Direct VPC egress 構成（コネクタ無し）で通る
- [ ] Secret の平文がコード/tfstate に無い（password_wo・secret 枠のみ）
- [ ] `ci-*`/`cd-*` トリガーが定義される（apply/実登録は #22 で確認）
