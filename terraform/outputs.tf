output "cloud_run_url" {
  description = "Cloud Run サービスの URL"
  value       = google_cloud_run_v2_service.app.uri
}

output "cloud_run_service_account" {
  description = "Cloud Run 実行 SA"
  value       = google_service_account.cloud_run.email
}

output "db_instance_name" {
  description = "Cloud SQL インスタンス名"
  value       = google_sql_database_instance.main.name
}

output "db_connection_name" {
  description = "Cloud SQL の接続名（project:region:instance）"
  value       = google_sql_database_instance.main.connection_name
}

output "db_private_ip" {
  description = "Cloud SQL の Private IP"
  value       = google_sql_database_instance.main.private_ip_address
}

output "db_name" {
  description = "データベース名"
  value       = google_sql_database.app.name
}

output "db_user" {
  description = "アプリ用 DB ユーザー名"
  value       = google_sql_user.app.name
}

output "database_url_secret" {
  description = "DATABASE_URL を格納する Secret Manager のシークレット名"
  value       = google_secret_manager_secret.database_url.secret_id
}

output "artifact_registry_repo" {
  description = "Artifact Registry リポジトリ ID"
  value       = google_artifact_registry_repository.app.repository_id
}

output "cloud_build_service_account" {
  description = "Cloud Build 実行 SA"
  value       = google_service_account.cloud_build.email
}

output "ci_trigger_name" {
  description = "CI 用 Cloud Build トリガー名"
  value       = google_cloudbuild_trigger.ci.name
}

output "cd_trigger_name" {
  description = "CD 用 Cloud Build トリガー名"
  value       = google_cloudbuild_trigger.cd.name
}

output "database_url_template" {
  description = "<PASSWORD> を実際の DB パスワードに置換して Secret Manager (database_url) に version として投入する"
  value       = "postgresql://${google_sql_user.app.name}:<PASSWORD>@${google_sql_database_instance.main.private_ip_address}:5432/${google_sql_database.app.name}?schema=public"
  # Private IP / DB ユーザーを含むためログ共有時の露出を避ける
  sensitive = true
}
