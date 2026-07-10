# Week 8 課題: TODO アプリ用 GCP インフラの Terraform 化

- date: 2026-07-10
- topic: VPC / IAM / Cloud Run / Cloud SQL(Private IP) + Bastion + IAP を Terraform で定義し、apply して IAP トンネル経由 psql 疎通を確認するまで

## 実施内容

- `terraform/` を新規作成（worktree `feature/week8-terraform-infra` 上で作業）。
  - versions/providers/variables/services/network/database/iam/compute/outputs + terraform.tfvars + scripts/connect-db.sh + README。
- WSL 環境に gcloud (`~/google-cloud-sdk`) と terraform (`~/bin`) を sudo なしで導入。
- Google プロバイダ認証は ADC ではなく `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)` を利用（ADC 対話ログインが `!` 実行で不可のため）。
- gcp-infra-review-agent でレビュー → 指摘を反映。
- `terraform init → plan → apply` を実行し 29 リソースを作成。
- Bastion を起動し IAP トンネルを開設、pg8000 で `todo_app` として認証し `SELECT version()` → PostgreSQL 16.14 を確認（手順4の疎通確認完了）。確認後 Bastion 停止。

## 決定事項

- リージョン `asia-northeast1`、Cloud SQL は `POSTGRES_16` / `db-f1-micro` / ZONAL / Private IP only。
- Cloud SQL は edition 未指定だと ENTERPRISE_PLUS になり db-f1-micro 不可 → `settings.edition = "ENTERPRISE"` を明示。
- IAP はインスタンス単位 IAM 設定が権限不足（非オーナー・403）→ プロジェクト単位 `roles/iap.tunnelResourceAccessor` で付与。
- DB パスワードは Secret Manager 管理だが実行ユーザーは読取不可 → ローカル state（`terraform output -raw db_password`）から取得する運用。
- Bastion の DB プロキシは apt 非依存の `systemd-socket-proxyd` を採用（外部 IP / Cloud NAT なしのため）。Cloud SQL Private IP は Terraform 既知値を埋め込み、Bastion SA の cloudsql 権限は不要化。
- connect-db.sh は `exec` を使わない（Ctrl+C で trap による Bastion 自動停止を効かせるため）。
- 学習用のため `deletion_protection=false`、PITR 無効、PSA 接続は `deletion_policy=DELETE`（クリーンな撤去優先）。

## 現在のプロジェクト状態

- GCP `aixeed-training-2026-07` に apply 済み（VPC todo-vpc / Cloud SQL todo-db / Cloud Run todo-app / Bastion todo-bastion(停止) / SA 2 / Secret / IAP 権限）。
- Cloud Run URL: https://todo-app-fp4dzbx5qq-an.a.run.app
- state はローカル管理（GCS backend 未使用）。
- Week 8 の手順 1〜4 完了。アプリ本体デプロイ / CI/CD は Week 9（未着手）。

## 未解決事項

- 動作確認後の撤去（`terraform destroy`）。放置すると Cloud SQL + VPC コネクタが常時課金。
- 本番化時: GCS backend 化、REGIONAL 冗長化、Cloud Run ingress を LB 内部限定、Direct VPC egress の検討、ラベル付与。
