# =============================================================================
# Cloud Run（空コンテナのプレースホルダ）+ Bastion VM
# =============================================================================

# --- Cloud Run サービス ---
# アプリ本体のデプロイは Week 9。ここではサービス定義のみ（プレースホルダ画像）。
resource "google_cloud_run_v2_service" "app" {
  name     = "${var.name_prefix}-app"
  project  = var.project_id
  location = var.region

  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    # VPC コネクタ経由で Cloud SQL の Private IP へ到達可能にする
    vpc_access {
      connector = google_vpc_access_connector.main.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      # 空コンテナ（Google 公式の hello サンプル）。Week 9 で実アプリに差し替える。
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 8080
      }

      # Week 9 の DB 接続に向けた配線（hello コンテナは未使用）
      env {
        name  = "DATABASE_HOST"
        value = google_sql_database_instance.main.private_ip_address
      }
      env {
        name  = "DATABASE_NAME"
        value = var.db_name
      }
      env {
        name  = "DATABASE_USER"
        value = var.db_user
      }
      env {
        name = "DATABASE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [google_project_iam_member.cloud_run_secret_accessor]
}

# --- Bastion VM ---
resource "google_compute_instance" "bastion" {
  name         = "${var.name_prefix}-bastion"
  project      = var.project_id
  zone         = var.zone
  machine_type = "e2-micro"
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.bastion.id
    # 外部 IP なし（IAP 経由でのみアクセス）
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  # 起動時に :5432 で Cloud SQL(Private IP) への TCP リレーを立てる。
  # Debian 12 同梱の systemd-socket-proxyd を使うため apt も実行時 gcloud も不要
  # （Bastion は外部 IP / Cloud NAT なしのため外部ネットへ出られない前提）。
  # Cloud SQL の Private IP は Terraform 既知値を直接埋め込む。
  metadata_startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    CLOUD_SQL_IP="${google_sql_database_instance.main.private_ip_address}"
    PROXY=/usr/lib/systemd/systemd-socket-proxyd
    [ -x "$PROXY" ] || PROXY=/lib/systemd/systemd-socket-proxyd
    printf '[Socket]\nListenStream=5432\n[Install]\nWantedBy=sockets.target\n' \
      > /etc/systemd/system/cloudsql-proxy.socket
    printf '[Unit]\nRequires=cloudsql-proxy.socket\nAfter=cloudsql-proxy.socket\n[Service]\nExecStart=%s %s:5432\n' \
      "$PROXY" "$CLOUD_SQL_IP" > /etc/systemd/system/cloudsql-proxy.service
    systemctl daemon-reload
    systemctl enable --now cloudsql-proxy.socket
  EOT

  # 使用時のみ起動する（初期状態は停止＝課金最小化）
  desired_status = "TERMINATED"

  # startup script が Cloud SQL の IP を参照するため依存を明示
  depends_on = [google_sql_database_instance.main]
}
