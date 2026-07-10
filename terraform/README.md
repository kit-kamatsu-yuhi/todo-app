# TODO アプリ用 GCP インフラ（Terraform）

Week 8 課題。TODO アプリの土台となる GCP リソースを Terraform で定義する。
アプリ本体のデプロイと CI/CD は Week 9 で扱うため、Cloud Run は空コンテナ（プレースホルダ）とする。

## 構成要素

| リソース | 内容 |
|---------|------|
| VPC | `todo-vpc`（カスタムサブネット） |
| サブネット | Bastion 用 `10.10.0.0/24` + Serverless VPC Access コネクタ `/28`（`10.8.0.0/28`） |
| Cloud SQL | PostgreSQL 16 / Private IP only / Public IP 無効 / PSA レンジ予約 |
| IAM | `todo-run-sa`（Cloud Run 用）・`todo-bastion-sa`（踏み台用）を最小権限で作成 |
| Cloud Run | `todo-app`（hello 画像・VPC コネクタ経由で Private IP 到達可能） |
| Bastion | `todo-bastion`（e2-micro / 外部 IP なし / systemd-socket-proxyd で DB プロキシ / 既定は停止） |
| IAP | Bastion への SSH / DB トンネルを指定ユーザーにのみ許可 |
| Secret Manager | `todo-db-password`（自動生成パスワード） |

## ネットワーク経路

```
Cloud Run --(VPC connector, PRIVATE_RANGES_ONLY)--> Cloud SQL(Private IP)
手元PC --(IAP tunnel)--> Bastion(systemd-socket-proxyd :5432) --> Cloud SQL(Private IP):5432
```

## 前提

- gcloud CLI 認証済み（`gcloud auth login`）
- 対象プロジェクトで課金有効・必要 API 有効化済み
- Terraform >= 1.5

## 使い方

```bash
cd terraform

# 初期化 → 差分確認 → 適用
terraform init
terraform plan
terraform apply

# 出力の確認
terraform output
```

`terraform.tfvars` で `project_id` と `iap_user` を指定する。既定リージョンは `asia-northeast1`。

## IAP トンネル経由の psql 疎通確認

```bash
# トンネルを開く（フォアグラウンド。Bastion を起動し socat 待受を確認してトンネル開設）
./scripts/connect-db.sh

# 別ターミナルで psql 接続。パスワードは以下いずれかで取得する。
#   ローカル state から（Secret Manager 読取権限が無い環境はこちら）:
terraform output -raw db_password
#   権限があれば Secret Manager から:
#   gcloud secrets versions access latest --secret=todo-db-password --project=aixeed-training-2026-07
psql -h localhost -p 15432 -U todo_app -d todo -c "SELECT version();"
```

終了は `Ctrl+C`。Bastion VM は自動停止する（課金最小化）。

## 撤去

```bash
terraform destroy
```

学習用のため削除保護は無効化してある（`deletion_protection = false`）。

## 補足・本番との差分

- state はローカル管理。本番では GCS backend（バケット + バージョニング）へ移行する。
- 学習用に `db-f1-micro` / `availability_type = ZONAL`。本番は用途に応じて上げる。
- OS Login / SSH には `roles/iap.tunnelResourceAccessor` に加えプロジェクトの SSH 権限が要る。
  本プロジェクトのオーナー/編集者であれば充足する。
