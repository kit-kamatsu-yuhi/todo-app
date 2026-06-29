---
name: aws-infrastructure
description: サーバー+クライアント型アーキテクチャ向けの AWS インフラ Terraform コードを生成する
user_invocable: true
command: /aws-infra
---

# AWS Infrastructure

サーバー+クライアント型アーキテクチャ向けの AWS Terraform コードを生成するスキル。
生成後は aws-infra-review-agent で検証する「生成→検証」ワークフローを推奨する。

## 対象サービス

### コンピュート

| サービス | 用途 | 選定基準 |
|---------|------|---------|
| App Runner | アプリケーションサーバー（サーバーサイド + API） | シンプルな構成、スケールゼロ対応 |
| ECS Fargate | アプリケーションサーバー（サーバーサイド + API） | 柔軟な構成、サイドカー・タスク定義が必要な場合 |
| EC2 | 踏み台サーバー（SSH 経由の DB アクセス用） | -- |

### データベース

| サービス | 用途 | 選定基準 |
|---------|------|---------|
| RDS (PostgreSQL) | OLTP ワークロード | 小〜中規模、コスト重視 |
| Aurora PostgreSQL | OLTP + 分析ワークロード | 大規模、高性能要求 |
| Aurora Global Database | グローバル分散 OLTP | マルチリージョン要求 |

### ネットワーク・セキュリティ

| サービス | 用途 |
|---------|------|
| VPC | プライベートネットワーク |
| ALB (Application Load Balancer) | HTTPS ロードバランシング |
| AWS WAF | WAF（Web Application Firewall） |
| AWS Shield | DDoS 防御 |
| Route 53 | カスタムドメイン管理 |

### 運用

| サービス | 用途 |
|---------|------|
| Secrets Manager | シークレット管理 |
| IAM | アクセス制御（ロール + ポリシーベース） |
| CloudWatch Logs | ログ集約 |
| CodeBuild | CI ビルド・テスト |
| CodePipeline | CD パイプライン |
| ECR | コンテナイメージレジストリ |

## IAM 設計方針

**原則: ユーザーにヒアリングし、不要なロールは作らない。**

サービス用の IAM ロールは必ず作成する。人間用の IAM ユーザー / ロールはプロジェクトの体制に応じて取捨選択する。

### サービス用 IAM ロール（必須）

| ロール | 用途 | ポリシー例 |
|-------|------|-----------|
| app-runner-role / ecs-task-role | アプリケーション実行用 | `AmazonRDSDataReadOnlyAccess`, カスタムポリシーで `secretsmanager:GetSecretValue` のみ許可（対象 ARN を限定） |
| codebuild-role | CI/CD パイプライン用 | `AmazonECR-FullAccess`（Push のみに絞ったカスタムポリシー推奨）, `CloudWatchLogsFullAccess` |
| bastion-role | 踏み台サーバー用（使用時のみ） | `AmazonRDSDataReadOnlyAccess` |

### 人間用 IAM（ヒアリング後に決定）

AWS マネージドポリシーで足りる場合はそちらを使う。カスタムポリシーは必要な場合のみ作成する。

| ロール | AWS マネージドポリシー | カスタムが必要なケース |
|--------|---------------------|---------------------|
| admin | `AdministratorAccess` | マネージドで十分 |
| viewer | `ReadOnlyAccess` | マネージドで十分 |
| developer | -- | デプロイ + ログ閲覧 + Secret 読取など、マネージドでは広すぎるため個別ポリシーを組み合わせる |

developer 向けポリシー構成例（必要に応じて調整）:
- App Runner / ECS デプロイ権限
- CloudWatch Logs 閲覧
- Secrets Manager 閲覧（値の読取は除外）
- RDS 接続情報閲覧

### ヒアリング項目

生成時にユーザーに確認する:
- プロジェクトに何人関わるか（1人なら admin のみで十分）
- developer ロールが必要か（デプロイ権限の分離が必要か）
- viewer ロールが必要か（ステークホルダーの閲覧用途があるか）
- コンピュートの選択: App Runner（シンプル） or ECS Fargate（柔軟）

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
│   ├── network/         # VPC, サブネット, セキュリティグループ
│   ├── database/        # RDS / Aurora
│   ├── compute/         # App Runner or ECS Fargate, EC2（踏み台）
│   ├── security/        # WAF, Shield, IAM
│   ├── dns/             # Route 53, カスタムドメイン
│   ├── secrets/         # Secrets Manager
│   ├── logging/         # CloudWatch Logs
│   └── ci-cd/           # CodeBuild, CodePipeline, ECR
```

## デプロイ戦略

### git-tag デプロイ

1. `v*` タグの push をトリガーに CodePipeline が起動する
2. CodeBuild がコンテナイメージをビルドし ECR に push する
3. staging 環境に自動デプロイする
4. 手動承認後に production 環境にデプロイする

### 環境分離

| 環境 | 用途 | デプロイ |
|------|------|---------|
| dev | 開発 | ブランチ push で自動 |
| staging | ステージング | git-tag で自動 |
| production | 本番 | staging 承認後 |

### 環境分離の実現方法

- AWS アカウント分離を推奨（AWS Organizations）
- 最低でも VPC レベルで分離する
- Terraform workspace または tfvars で環境を切り替える

## 生成→検証ワークフロー

1. このスキルで Terraform コードを生成する
2. `terraform fmt` でフォーマットする
3. `terraform validate` で構文検証する
4. **aws-infra-review-agent** で以下を検証する:
   - セキュリティ設定（IAM 最小権限、ネットワーク分離）
   - コスト最適化（インスタンスサイズ、リージョン選択）
   - 高可用性（マルチAZ、バックアップ設定）
   - ベストプラクティス準拠
5. 検証結果に基づき修正する

## 手動設定が必要な項目

以下は Terraform で自動化できない、または手動設定が推奨される項目:

| 項目 | 理由 | 手順 |
|------|------|------|
| ACM 証明書の DNS 検証 | ドメインの DNS レコード追加が必要 | ACM でリクエスト → Route 53 に CNAME レコード追加 |
| AWS Organizations 設定 | 組織ポリシーに依存 | AWS Console → Organizations |
| 課金アラーム | 初回のみ手動設定が必要 | AWS Console → Billing → Budgets |
| MFA 設定 | ルートアカウント・IAM ユーザーの MFA | AWS Console → IAM → MFA |

## App Runner vs ECS Fargate 選定基準

| 観点 | App Runner | ECS Fargate |
|------|-----------|-------------|
| セットアップ | 簡単（ソースコード or イメージ指定のみ） | やや複雑（タスク定義、サービス、クラスター） |
| スケールゼロ | 対応（課金停止） | 非対応（最低1タスク稼働） |
| VPC 統合 | VPC Connector 経由 | ネイティブ VPC 統合 |
| サイドカー | 非対応 | 対応 |
| カスタマイズ性 | 限定的 | 高い |
| ユースケース | シンプルな Web API、プロトタイプ | 本格的な本番ワークロード |

**推奨**: TODOアプリのような学習用途では App Runner で十分。本番ワークロードでは ECS Fargate を検討する。

## 関連スキル（Agent Plugins 知識）

awslabs/agent-plugins の知識を以下のスキルで補完する:

| スキル | 提供する知識 |
|-------|------------|
| aws-deploy | CDK/CloudFormation パターン、コスト見積もり、アーキテクチャ推奨 |
| aws-serverless | Lambda / API Gateway / Step Functions 設計 |
| aws-databases | DynamoDB / Aurora DSQL 等、RDS 以外の DB 選定 |
| aws-mcp | MCP サーバー切り替え（リアルタイム料金取得等の拡張機能） |

## 使い方

```
/aws-infra
```

### 対話フロー

1. プロジェクト要件のヒアリング
   - アプリケーション種別（Web API / フルスタック / etc.）
   - データベース要件（規模、可用性、分析ニーズ）
   - ドメイン要件
   - コンピュート選択（App Runner or ECS Fargate）
   - チーム体制（何人か、developer/viewer ロールが必要か）
2. Terraform コード生成
3. aws-infra-review-agent による検証
4. 修正・確定
