# =============================================================================
# VPC / サブネット / ファイアウォール / Private Service Access
# =============================================================================

resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.enabled]
}

# Bastion VM 用サブネット
resource "google_compute_subnetwork" "bastion" {
  name          = "${var.name_prefix}-bastion-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.bastion_subnet_cidr

  # Bastion は外部 IP を持たないため、Private Google Access を有効化して
  # gcloud / パッケージ取得などの Google API アクセスを可能にする
  private_ip_google_access = true
}

# Cloud Run → VPC egress 用の Serverless VPC Access コネクタ（/28 が必須）
resource "google_vpc_access_connector" "main" {
  name          = "${var.name_prefix}-connector"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = var.connector_cidr

  # 学習用途のため最小構成
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"

  depends_on = [google_project_service.enabled]
}

# IAP 経由の SSH（22）と DB トンネル（5432）のみを Bastion に許可する
resource "google_compute_firewall" "allow_iap" {
  name    = "${var.name_prefix}-allow-iap"
  project = var.project_id
  network = google_compute_network.main.id

  allow {
    protocol = "tcp"
    ports    = ["22", "5432"]
  }

  # IAP の送信元 IP レンジ（固定）
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["bastion"]
}

# =============================================================================
# Private Service Access（Cloud SQL の Private IP 用にレンジを予約）
# =============================================================================

resource "google_compute_global_address" "private_ip" {
  name          = "${var.name_prefix}-psa-range"
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

  # deletion_policy は未指定（デフォルト = destroy 時にピアリングを削除）。
  # 有効値は "ABANDON" のみ。撤去を繰り返す学習用途ではデフォルトの削除挙動が扱いやすい。
}
