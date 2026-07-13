# =============================================================================
# IAM: ワークロードごとの Service Account + 最小権限
# =============================================================================

data "google_project" "current" {
  project_id = var.project_id
}

# --- Cloud Run 実行用 SA ---
resource "google_service_account" "cloud_run" {
  account_id   = "${var.name_prefix}-run-sa"
  display_name = "Cloud Run (${var.name_prefix}) Service Account"
  project      = var.project_id

  depends_on = [google_project_service.enabled]
}

# Cloud Run: DB シークレット読取（secret 単位に限定）+ ログ書込。
# Direct VPC egress + パスワード認証で Private IP へ直結するため cloudsql.client は不要。
resource "google_secret_manager_secret_iam_member" "cloud_run_db_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# --- Cloud Build 実行用 SA ---
resource "google_service_account" "cloud_build" {
  account_id   = "${var.name_prefix}-build-sa"
  display_name = "Cloud Build (${var.name_prefix}) Service Account"
  project      = var.project_id

  depends_on = [google_project_service.enabled]
}

# デプロイに必要な最小権限（IAM 変更まで許す admin ではなく developer）
resource "google_project_iam_member" "cloud_build_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Artifact Registry への push は該当リポジトリ単位に限定する
resource "google_artifact_registry_repository_iam_member" "cloud_build_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.app.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Cloud Build SA が Cloud Run 実行 SA を actAs できるようにする（リソース単位・最小権限）。
# プロジェクト全体の serviceAccountUser は付与しない。
resource "google_service_account_iam_member" "build_act_as_run" {
  service_account_id = google_service_account.cloud_run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud_build.email}"
}

# 1st-gen トリガーがカスタム SA を使うため、Cloud Build サービスエージェントが
# ビルド SA のトークンを発行できるようにする（serviceAccountTokenCreator）。
resource "google_service_account_iam_member" "build_agent_token_creator" {
  service_account_id = google_service_account.cloud_build.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}
