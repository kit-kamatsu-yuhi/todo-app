terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # 学習用のためローカル state を使用する。
  # 本番運用では GCS backend（バケット + オブジェクトバージョニング）に切り替える。
}
