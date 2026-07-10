# =============================================================================
# IAM: ワークロードごとの Service Account + 最小権限
# =============================================================================

# --- Cloud Run 実行用 SA ---
resource "google_service_account" "cloud_run" {
  account_id   = "${var.name_prefix}-run-sa"
  display_name = "Cloud Run (${var.name_prefix}) Service Account"
  project      = var.project_id

  depends_on = [google_project_service.enabled]
}

# Cloud Run: Cloud SQL 接続 / Secret 読取 / ログ書込
resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# --- Bastion VM 用 SA ---
resource "google_service_account" "bastion" {
  account_id   = "${var.name_prefix}-bastion-sa"
  display_name = "Bastion (${var.name_prefix}) Service Account"
  project      = var.project_id

  depends_on = [google_project_service.enabled]
}

# Bastion は systemd-socket-proxyd で生 TCP リレーするだけで Cloud SQL の
# IAM 認証も describe も使わないため、cloudsql 系ロールは付与しない（最小権限）。
resource "google_project_iam_member" "bastion_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# =============================================================================
# IAP: 指定ユーザーに Bastion へのトンネルアクセスを許可
# =============================================================================
# インスタンス単位の IAP IAM 設定には iap.tunnelInstances.setIamPolicy
# （オーナー/iap.admin 相当）が必要。本プロジェクトの実行ユーザーは未保有のため、
# プロジェクト単位で tunnelResourceAccessor を付与する（projects.setIamPolicy で足りる）。
# プロジェクト単位でもトンネル先はこの VPC 内の Bastion に限られる。
resource "google_project_iam_member" "iap_tunnel_user" {
  project = var.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "user:${var.iap_user}"
}
