# =============================================================================
# Cloud SQL (PostgreSQL, Private IP only) + Secret Manager
# =============================================================================

# DATABASE_URL 用の Secret Manager 枠のみ作成する。
# 値の version は apply 後に GUI または gcloud で投入する。
resource "google_secret_manager_secret" "database_url" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

# Cloud SQL インスタンス（Public IP 無効・Private IP のみ）
resource "google_sql_database_instance" "main" {
  name             = "${var.name_prefix}-db"
  project          = var.project_id
  region           = var.region
  database_version = var.db_version

  # PSA の接続確立後に作成する
  depends_on = [google_service_networking_connection.private_vpc]

  # 学習用のため撤去しやすいよう削除保護を無効化する（本番では true）
  deletion_protection = false

  settings {
    tier    = var.db_tier
    edition = "ENTERPRISE" # 共有コア(db-f1-micro)は ENTERPRISE でのみ利用可
    # 学習用のため ZONAL（本番は REGIONAL で冗長化）
    availability_type     = "ZONAL"
    disk_size             = 10
    disk_autoresize       = true
    disk_autoresize_limit = 20 # 意図しない際限ない拡張を防ぐ

    ip_configuration {
      ipv4_enabled                                  = false # Public IP 禁止
      private_network                               = google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled = true
      # 学習用のため PITR は無効（WAL 保持のストレージ増を回避）
      point_in_time_recovery_enabled = false
    }

    # インスタンス側の削除保護も無効化する（学習用）
    deletion_protection_enabled = false
  }
}

resource "google_sql_database" "app" {
  name     = var.db_name
  project  = var.project_id
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "app" {
  name     = var.db_user
  project  = var.project_id
  instance = google_sql_database_instance.main.name

  password_wo         = var.db_password
  password_wo_version = var.db_password_version
}
