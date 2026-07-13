# CI: ci-* タグ push でテスト実行
resource "google_cloudbuild_trigger" "ci" {
  project         = var.project_id
  name            = "${var.name_prefix}-ci"
  description     = "CI: ci-* タグでテストを実行"
  service_account = google_service_account.cloud_build.id

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      tag = "^ci-.*$"
    }
  }

  build {
    # DB 非依存の build + 型チェックのみ（DB 統合テストは GitHub Actions の
    # postgres service で実行する。Cloud Build 既定ワーカーは Cloud SQL Private IP に到達不可）。
    step {
      name       = "node:22-slim"
      entrypoint = "bash"
      args       = ["-c", "apt-get update && apt-get install -y --no-install-recommends openssl && npm ci && npm run build && npx tsc --noEmit"]
    }
    options {
      logging = "CLOUD_LOGGING_ONLY"
    }
  }

  depends_on = [google_project_service.enabled]
}

# CD: cd-* タグ push でビルド→push→デプロイ
resource "google_cloudbuild_trigger" "cd" {
  project         = var.project_id
  name            = "${var.name_prefix}-cd"
  description     = "CD: cd-* タグでビルドしてデプロイ"
  service_account = google_service_account.cloud_build.id
  filename        = "cloudbuild.yaml"

  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      tag = "^cd-.*$"
    }
  }

  substitutions = {
    _REGION  = var.region
    _SERVICE = google_cloud_run_v2_service.app.name
    _REPO    = google_artifact_registry_repository.app.repository_id
  }

  depends_on = [google_project_service.enabled]
}
