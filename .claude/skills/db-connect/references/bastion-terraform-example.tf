#
# Bastion VM + IAP + VPC の Terraform サンプル
#
# /gcp-infra スキルで生成される構成の簡易版。
# 実プロジェクトでは /gcp-infra で完全な Terraform コードを生成し、
# gcp-infra-review-agent で検証することを推奨する。
#

variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "ゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "db_instance_name" {
  description = "Cloud SQL インスタンス名"
  type        = string
  default     = "main-db"
}

variable "bastion_instance_name" {
  description = "Bastion VM インスタンス名"
  type        = string
  default     = "bastion"
}

# --- VPC ---

resource "google_compute_network" "main" {
  name                    = "main-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "main-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = "10.0.0.0/24"
}

# --- Firewall: IAP 経由の SSH のみ許可 ---

resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # IAP のソース IP 範囲
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

# --- Cloud SQL (PostgreSQL, Private IP) ---

resource "google_compute_global_address" "private_ip" {
  name          = "private-ip-address"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]
}

resource "google_sql_database_instance" "main" {
  name             = var.db_instance_name
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  depends_on = [google_service_networking_connection.private_vpc]

  settings {
    tier              = "db-custom-1-3840"
    availability_type = "ZONAL"

    ip_configuration {
      ipv4_enabled    = false # Public IP 禁止
      private_network = google_compute_network.main.id
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    deletion_protection_enabled = true
  }
}

# --- Bastion VM ---

resource "google_service_account" "bastion" {
  account_id   = "bastion-sa"
  display_name = "Bastion Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "bastion_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

resource "google_compute_instance" "bastion" {
  name         = var.bastion_instance_name
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
    subnetwork = google_compute_subnetwork.main.id
    # Public IP なし（IAP 経由でアクセス）
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  # startup script: socat で Cloud SQL へのプロキシを起動
  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update && apt-get install -y socat
    CLOUD_SQL_IP=$(gcloud sql instances describe ${var.db_instance_name} \
      --project=${var.project_id} \
      --format='value(ipAddresses[0].ipAddress)')
    socat TCP-LISTEN:5432,fork,reuseaddr TCP:$CLOUD_SQL_IP:5432 &
  EOF

  # 使用時のみ起動するため、初期状態は停止
  desired_status = "TERMINATED"
}

# --- IAP 設定 ---

resource "google_iap_tunnel_instance_iam_member" "bastion" {
  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.bastion.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "user:YOUR_EMAIL@example.com" # ← 実際のユーザーに変更
}
