# =============================================================================
# Cloud SQL (PostgreSQL, Private IP only) + Secret Manager
# =============================================================================

# アプリ用 DB ユーザーのパスワードを自動生成する
resource "random_password" "db" {
  length = 24
  # psql / 接続文字列で扱いやすい記号のみに限定する
  special          = true
  override_special = "_-"
}

# 生成したパスワードを Secret Manager で管理する
resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-db-password"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
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

  # 値は random_password から参照する（コード上にリテラルは持たない）
  password = (
    random_password.db.result
  )
}
