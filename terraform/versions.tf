terraform {
  # password_wo（write-only 引数）を使うため 1.11 以上が必須
  required_version = ">= 1.11"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # 学習用のためローカル state を使用する。
  # 本番運用では GCS backend（バケット + オブジェクトバージョニング）に切り替える。
}
