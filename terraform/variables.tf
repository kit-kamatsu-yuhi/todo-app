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
  description = "デフォルトゾーン"
  type        = string
  default     = "asia-northeast1-a"
}

variable "name_prefix" {
  description = "リソース名の接頭辞"
  type        = string
  default     = "todo"
}

# --- ネットワーク CIDR ---

variable "egress_subnet_cidr" {
  description = "Direct VPC egress 用サブネットの CIDR"
  type        = string
  default     = "10.10.0.0/24"
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

variable "db_password" {
  description = "アプリ用 DB ユーザーのパスワード（未コミットの tfvars で渡す。password_wo 経由で state に平文を残さない）"
  type        = string
  sensitive   = true
}

variable "db_password_version" {
  description = "DB パスワードのローテーション用バージョン。db_password を変えたら increment する"
  type        = number
  default     = 1
}

# --- Cloud Run ---

variable "invoker_user" {
  description = "Cloud Run を呼び出せるユーザー（org ポリシーで allUsers 不可のため認証アクセス用に付与）"
  type        = string
  default     = "kamatsu.yuhi@gcp.k-idea.jp"
}

# --- Cloud Build ---

variable "github_owner" {
  description = "Cloud Build トリガーが参照する GitHub リポジトリのオーナー"
  type        = string
}

variable "github_repo" {
  description = "Cloud Build トリガーが参照する GitHub リポジトリ名"
  type        = string
}
