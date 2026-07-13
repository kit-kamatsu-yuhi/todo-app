# =============================================================================
# VPC / Direct VPC egress サブネット / Private Service Access
# =============================================================================

resource "google_compute_network" "main" {
  name                    = "${var.name_prefix}-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.enabled]
}

# Cloud Run Direct VPC egress 用サブネット
resource "google_compute_subnetwork" "egress" {
  name          = "${var.name_prefix}-egress-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.egress_subnet_cidr

  # Direct VPC egress 経由の Cloud Run から Google API へ到達できるようにする
  private_ip_google_access = true
}

# =============================================================================
# Private Service Access（Cloud SQL の Private IP 用にレンジを予約）
# =============================================================================

resource "google_compute_global_address" "private_ip" {
  name          = "${var.name_prefix}-psa-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 24 # 学習用途には /24 で十分（/16 は過大予約）
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip.name]

  # deletion_policy は未指定（デフォルト = destroy 時にピアリングを削除）。
  # 有効値は "ABANDON" のみ。撤去を繰り返す学習用途ではデフォルトの削除挙動が扱いやすい。
}
