# TODO アプリ用 GCP インフラ（Terraform）

## 構成要素

| リソース | 内容 |
|---------|------|
| VPC | `todo-vpc`（カスタムサブネット） |
| egress サブネット | `todo-egress-subnet`（`10.10.0.0/24`、Cloud Run Direct VPC egress 用） |
| Cloud SQL | PostgreSQL 16 / Private IP only / Public IP 無効 / PSA レンジ予約 |
| Cloud Run | `todo-app`（公開、Direct VPC egress、min instance 0 / max instance 2） |
| Secret Manager | `todo-database-url`（枠のみ作成。値は Terraform では投入しない） |
| Artifact Registry | `todo-app`（Docker イメージ格納） |
| Cloud Build | `ci-*` タグでテスト、`cd-*` タグでビルド・push・Cloud Run デプロイ |
| IAM | `todo-run-sa`（Cloud Run 用）、`todo-build-sa`（Cloud Build 用） |

## ネットワーク経路

```text
Cloud Run --Direct VPC egress--> Cloud SQL Private IP
```

## 手動前提

Cloud Build の GitHub 連携は 1st-gen GitHub App のインストールとリポジトリ接続を GCP Console で手動実施する。接続が完了するまで `google_cloudbuild_trigger` の apply は失敗する。

## 機密の扱い

`db_password` はコミットしない tfvars で渡す。例:

```hcl
# secrets.auto.tfvars
db_password = "..."
```

`terraform/.gitignore` で `*.auto.tfvars` は除外済み。`terraform.tfvars`、コード、outputs には DB パスワードや実 DATABASE_URL を書かない。DB ユーザーの password は `password_wo` で渡し、state に平文を残さない。

## 前提

- Terraform **1.11 以上**（`password_wo` 書き込み専用引数を使用）
- gcloud 認証済み（terraform は ADC もしくは `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)` を使用）
- `terraform.tfvars` に `project_id` / `github_owner` / `github_repo` を指定。`db_password` は `secrets.auto.tfvars`（未コミット）で渡す

## 使い方（二段階 apply）

Cloud Run は `DATABASE_URL` の Secret を `latest` で参照するため、**Secret に version が無いと初回 apply で Cloud Run 作成に失敗する**。先に Secret 枠と Cloud SQL を作り、値を投入してから全体を apply する。

```bash
cd terraform
terraform init

# 1) Secret 枠と Cloud SQL を先に作成
terraform apply \
  -target=google_secret_manager_secret.database_url \
  -target=google_sql_database_instance.main \
  -target=google_sql_database.app \
  -target=google_sql_user.app

# 2) Private IP を確認し、DATABASE_URL を Secret に投入（値は GUI/gcloud で。コードには置かない）
terraform output -raw db_private_ip
printf '%s' 'postgresql://todo_app:<PW>@<PrivateIP>:5432/todo?schema=public' \
  | gcloud secrets versions add todo-database-url \
      --project=aixeed-training-2026-07 --data-file=-

# 3) 残り（Cloud Run / Cloud Build / Artifact Registry / IAM）を apply
terraform apply
```

その後 `cd-*` タグを push すると Cloud Build が実イメージをビルドして Artifact Registry へ push し、Cloud Run にデプロイする（マイグレーションはコンテナ起動時に実行）。

## CI/CD

- `ci-*` タグ push: `npm ci && npm run build && npx tsc --noEmit`（DB 非依存の build + 型チェック）
- `cd-*` タグ push: Docker build、Artifact Registry push、Cloud Run deploy
- CD のビルド定義はリポジトリルートの `cloudbuild.yaml`
- DB 統合テスト（PostgreSQL 必須）は GitHub Actions（`.github/workflows/test.yml`）の postgres service で実行する

## 撤去

```bash
cd terraform
terraform destroy
```

学習用のため Cloud Run と Cloud SQL の削除保護は無効化している。
