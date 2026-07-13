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

  depends_on = [google_project_iam_member.cloud_run_secret_accessor]
}

# 到達用の invoker。組織ポリシーで allUsers（完全公開）が禁止されているため、
# 指定ユーザー（ドメイン内アカウント）へプロジェクト単位で run.invoker を付与する。
# 到達確認は認証付き（gcloud run services proxy / identity-token）で行う。
resource "google_project_iam_member" "invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "user:${var.invoker_user}"

  depends_on = [google_cloud_run_v2_service.app]
}
