# 必要な API を有効化する。
# 本プロジェクトでは既に有効化済みだが、Terraform を自己完結にするため明示する。
# 既に有効な API に対しては no-op となる。
locals {
  required_services = [
    "compute.googleapis.com",           # VPC / サブネット
    "run.googleapis.com",               # Cloud Run
    "sqladmin.googleapis.com",          # Cloud SQL
    "servicenetworking.googleapis.com", # Private Service Access
    "secretmanager.googleapis.com",     # DATABASE_URL 管理
    "iam.googleapis.com",               # Service Account / IAM
    "cloudbuild.googleapis.com",        # Cloud Build トリガー
    "artifactregistry.googleapis.com",  # Docker イメージ格納
  ]
}

resource "google_project_service" "enabled" {
  for_each = toset(local.required_services)

  project = var.project_id
  service = each.value

  # destroy 時に API を無効化しない（他リソースへの影響を避ける）
  disable_on_destroy         = false
  disable_dependent_services = false
}
