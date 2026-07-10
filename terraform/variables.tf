variable "project_id" {
  description = "デプロイ先の GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "Bastion VM のゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "todo"
}

variable "iap_user" {
  description = "IAP トンネル経由の SSH / TCP アクセスを許可する Google アカウント（user:<email> の email 部分）"
  type        = string
}

# --- ネットワーク CIDR ---

variable "bastion_subnet_cidr" {
  description = "Bastion 用サブネットの CIDR"
  type        = string
  default     = "10.10.0.0/24"
}

variable "connector_cidr" {
  description = "Serverless VPC Access コネクタ用の /28 CIDR（Cloud Run → VPC egress 用）"
  type        = string
  default     = "10.8.0.0/28"
}

# --- Cloud SQL ---

variable "db_version" {
  description = "Cloud SQL のデータベースエンジンバージョン"
  type        = string
  default     = "POSTGRES_16"
}

variable "db_tier" {
  description = "Cloud SQL のマシンタイプ（学習用は db-f1-micro が最安）"
  type        = string
  default     = "db-f1-micro"
}

variable "db_name" {
  description = "作成するデータベース名"
  type        = string
  default     = "todo"
}

variable "db_user" {
  description = "アプリ用 DB ユーザー名"
  type        = string
  default     = "todo_app"
}
