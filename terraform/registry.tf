resource "google_artifact_registry_repository" "app" {
  project       = var.project_id
  location      = var.region
  repository_id = "${var.name_prefix}-app"
  format        = "DOCKER"
  description   = "TODO アプリの Docker イメージ"
  depends_on    = [google_project_service.enabled]
}
