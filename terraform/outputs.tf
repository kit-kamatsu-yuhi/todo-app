output "cloud_run_url" {
  description = "Cloud Run サービスの URL"
  value       = google_cloud_run_v2_service.app.uri
}

output "cloud_run_service_account" {
  description = "Cloud Run 実行 SA"
  value       = google_service_account.cloud_run.email
}

output "bastion_name" {
  description = "Bastion VM のインスタンス名"
  value       = google_compute_instance.bastion.name
}

output "bastion_zone" {
  description = "Bastion VM のゾーン"
  value       = google_compute_instance.bastion.zone
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

output "db_password_secret" {
  description = "DB パスワードを格納した Secret Manager のシークレット名"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "psql_connect_hint" {
  description = "IAP トンネル経由での接続手順（scripts/connect-db.sh 実行後）"
  value       = "psql -h localhost -p 15432 -U ${google_sql_user.app.name} -d ${google_sql_database.app.name}"
}

# ローカル検証用。Secret Manager を読めない環境向けに state から取得する。
# `terraform output -raw db_password` で取り出す。state 同様コミットしないこと。
output "db_password" {
  description = "アプリ用 DB ユーザーのパスワード（機微・ローカル state 由来）"
  value       = random_password.db.result
  sensitive   = true
}
