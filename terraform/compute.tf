# =============================================================================
# Cloud Run（Cloud Build が実イメージをデプロイ）
# =============================================================================

# --- Cloud Run サービス ---
resource "google_cloud_run_v2_service" "app" {
  name     = "${var.name_prefix}-app"
  project  = var.project_id
  location = var.region

  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    # Direct VPC egress で Cloud SQL の Private IP へ到達する
    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"
      network_interfaces {
        network    = google_compute_network.main.name
        subnetwork = google_compute_subnetwork.egress.name
      }
    }

    containers {
      # 初回はプレースホルダ（distroless の hello。migrate は実イメージの CMD が実行する）。
      # 実イメージは Cloud Build (cd-*) がデプロイする。
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 3000
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  lifecycle {
    # 実イメージ・起動コマンドは Cloud Build がデプロイ時に反映するため TF は追従しない
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[0].command,
      template[0].containers[0].args,
    ]
  }

  depends_on = [google_secret_manager_secret_iam_member.cloud_run_db_secret]
}

# 公開（未認証許可）。事故防止に変数でゲートする（既定は公開）。
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_unauthenticated ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.app.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
