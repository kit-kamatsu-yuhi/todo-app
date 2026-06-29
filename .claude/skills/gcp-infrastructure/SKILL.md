---
name: gcp-infrastructure
description: サーバー+クライアント型アーキテクチャ向けの GCP インフラ Terraform コードを生成する
user_invocable: true
command: /gcp-infra
---

# GCP Infrastructure

サーバー+クライアント型アーキテクチャ向けの GCP Terraform コードを生成するスキル。
生成後は gcp-infra-review-agent で検証する「生成→検証」ワークフローを推奨する。

## 対象サービス

### コンピュート

| サービス | 用途 |
|---------|------|
| Cloud Run | アプリケーションサーバー（サーバーサイド + API） |
| Compute Engine | 踏み台サーバー（SSH 経由の DB アクセス用） |

### データベース

| サービス | 用途 | 選定基準 |
|---------|------|---------|
| Cloud SQL (PostgreSQL) | OLTP ワークロード | 小〜中規模、コスト重視 |
| AlloyDB | OLTP + 分析ワークロード | 大規模、高性能要求 |
| Spanner | グローバル分散 OLTP | マルチリージョン要求 |

### ネットワーク・セキュリティ

| サービス | 用途 |
|---------|------|
| VPC | プライベートネットワーク |
| Load Balancer | HTTPS ロードバランシング |
| Cloud Armor | WAF / DDoS 防御 |
| IAP | Identity-Aware Proxy（条件付き導入） |
| Cloud DNS | カスタムドメイン管理 |

### 運用

| サービス | 用途 |
|---------|------|
| Secret Manager | シークレット管理 |
| IAM | アクセス制御（SA 必須 + 人間用はヒアリング後に決定） |
| Cloud Logging | ログ集約 |
| Cloud Build | CI/CD パイプライン |

## IAM 設計方針

**原則: ユーザーにヒアリングし、不要なロールは作らない。**

SA（Service Account）は必ず作成する。人間用のロールはプロジェクトの体制に応じて取捨選択する。

### Service Account（必須）

| SA | 用途 | ロール例 |
|----|------|---------|
| cloud-run-sa | Cloud Run サービス実行用 | `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`, `roles/logging.logWriter` |
| cloud-build-sa | CI/CD パイプライン用 | `roles/run.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.writer` |
| bastion-sa | 踏み台サーバー用（使用時のみ） | `roles/cloudsql.client` |

### 人間用ロール（ヒアリング後に決定）

GCP 基本ロールで足りる場合はそちらを使う。カスタムロールは必要な場合のみ作成する。

| ロール | GCP 基本ロール | カスタムが必要なケース |
|--------|---------------|---------------------|
| admin | `roles/owner` or `roles/editor` | 基本ロールで十分 |
| viewer | `roles/viewer` | 基本ロールで十分 |
| developer | — | Cloud Run デプロイ + ログ閲覧 + Secret 読取など、基本ロールでは広すぎるため個別ロールを組み合わせる |

developer 向けロール構成例（必要に応じて調整）:
- `roles/run.developer` — Cloud Run デプロイ
- `roles/logging.viewer` — ログ閲覧
- `roles/secretmanager.viewer` — Secret 一覧閲覧
- `roles/cloudsql.viewer` — DB 接続情報閲覧

### ヒアリング項目

生成時にユーザーに確認する:
- プロジェクトに何人関わるか（1人なら owner のみで十分）
- developer ロールが必要か（デプロイ権限の分離が必要か）
- viewer ロールが必要か（ステークホルダーの閲覧用途があるか）

## Terraform コード構成

```
terraform/
├── main.tf              # プロバイダー設定、バックエンド
├── variables.tf         # 入力変数
├── outputs.tf           # 出力値
├── versions.tf          # required_providers
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── modules/
│   ├── network/         # VPC, サブネット, ファイアウォール
│   ├── database/        # Cloud SQL / AlloyDB / Spanner
│   ├── compute/         # Cloud Run, Compute Engine（踏み台）
│   ├── security/        # Cloud Armor, IAP, IAM
│   ├── dns/             # Cloud DNS, カスタムドメイン
│   ├── secrets/         # Secret Manager
│   ├── logging/         # Cloud Logging
│   └── ci-cd/           # Cloud Build, git-tag デプロイ
```

## デプロイ戦略

### git-tag デプロイ

1. `v*` タグの push をトリガーに Cloud Build が起動する
2. Cloud Build がコンテナイメージをビルドする
3. staging 環境に自動デプロイする
4. 手動承認後に production 環境にデプロイする

### 環境分離

| 環境 | 用途 | デプロイ |
|------|------|---------|
| dev | 開発 | ブランチ push で自動 |
| staging | ステージング | git-tag で自動 |
| production | 本番 | staging 承認後 |

## 生成→検証ワークフロー

1. このスキルで Terraform コードを生成する
2. `terraform fmt` でフォーマットする
3. `terraform validate` で構文検証する
4. **gcp-infra-review-agent** で以下を検証する:
   - セキュリティ設定（IAM 最小権限、ネットワーク分離）
   - コスト最適化（インスタンスサイズ、リージョン選択）
   - 高可用性（レプリカ、バックアップ設定）
   - ベストプラクティス準拠
5. 検証結果に基づき修正する

## 手動設定が必要な項目

以下は Terraform で自動化できないため、手動で設定する:

| 項目 | 理由 | 手順 |
|------|------|------|
| OAuth 同意画面 | Google Cloud Console でのみ設定可能 | GCP Console → API とサービス → OAuth 同意画面 |
| OAuth クライアント ID | Console での作成が推奨 | GCP Console → 認証情報 → OAuth 2.0 クライアント ID |
| ドメイン所有権の確認 | DNS レコードの手動追加が必要 | Google Search Console でドメイン確認 |
| 課金アカウントのリンク | 組織ポリシーに依存 | GCP Console → 課金 |

## 使い方

```
/gcp-infra
```

### 対話フロー

1. プロジェクト要件のヒアリング
   - アプリケーション種別（Web API / フルスタック / etc.）
   - データベース要件（規模、可用性、分析ニーズ）
   - ドメイン要件
   - IAP の要否
   - チーム体制（何人か、developer/viewer ロールが必要か）
2. Terraform コード生成
3. gcp-infra-review-agent による検証
4. 修正・確定
