# =============================================================================
# Cloud Run Job（DB マイグレーション実行用）
# =============================================================================

resource "google_cloud_run_v2_job" "migrate" {
  name     = "${var.name_prefix}-migrate"
  project  = var.project_id
  location = var.region

  deletion_protection = false

  template {
    template {
      # Prisma は失敗した migration を記録するため、リトライしても成功せず失敗検知が遅れるだけ。
      # Cloud Run Job 側ではリトライしない。
      max_retries = 0

      # 既存の Cloud Run 実行 SA を流用する。secretAccessor がプロジェクト単位付与のため追加 IAM は不要。
      service_account = google_service_account.cloud_run.email

      # Direct VPC egress で Cloud SQL の Private IP へ到達する
      vpc_access {
        egress = "PRIVATE_RANGES_ONLY"
        network_interfaces {
          network    = google_compute_network.main.name
          subnetwork = google_compute_subnetwork.egress.name
        }
      }

      containers {
        # 初回はプレースホルダ。実イメージは Cloud Build (cd-*) が反映する。
        image = "us-docker.pkg.dev/cloudrun/container/hello"

        # app イメージの CMD を上書きして migrate deploy のみ実行する。
        command = ["node"]
        args    = ["node_modules/prisma/build/index.js", "migrate", "deploy"]

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.database_url_migrate.secret_id
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    # 実イメージは CD の gcloud run jobs update --image が反映するため TF は追従しない。
    # command / args は Terraform の初期設定から変えず、差分ノイズだけを抑止する。
    ignore_changes = [
      template[0].template[0].containers[0].image,
      template[0].template[0].containers[0].command,
      template[0].template[0].containers[0].args,
    ]
  }

  depends_on = [google_project_iam_member.cloud_run_secret_accessor]
}
