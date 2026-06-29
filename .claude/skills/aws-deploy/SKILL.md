---
name: aws-deploy
description: AWS デプロイ知識（アーキテクチャ推奨・コスト見積もり・CDK/CloudFormation/Terraform による IaC 生成）
user_invocable: false
---

# AWS Deploy

awslabs/agent-plugins の deploy-on-aws 知識に基づく AWS デプロイスキル。
アプリコードを解析し、アーキテクチャ推奨 → コスト見積もり → IaC 生成のフローを提供する。

## デプロイワークフロー

1. **アプリコード解析**: 言語・フレームワーク・依存関係・DB 要件を特定する
2. **AWS サービス推奨**: アプリ特性に基づきコンピュート・DB・ネットワークを選定する
3. **コスト見積もり**: 推奨構成の月額コストを概算する（詳細は `references/cost-estimation.md`）
4. **IaC 生成**: Terraform / CDK / CloudFormation でインフラコードを生成する

## アーキテクチャ推奨ロジック

### コンピュート選定

| アプリ特性 | 推奨サービス | 理由 |
|-----------|------------|------|
| シンプルな Web API / プロトタイプ | App Runner | セットアップが簡単、スケールゼロ対応 |
| サイドカー・複雑なネットワーク要件 | ECS Fargate | 柔軟なタスク定義、ネイティブ VPC 統合 |
| イベント駆動・短時間処理 | Lambda | サーバーレス、ミリ秒課金 |
| SPA + API | Amplify Hosting + Lambda | フロント・バックエンド統合 |

### DB 選定

| 要件 | 推奨サービス | 理由 |
|------|------------|------|
| OLTP（小〜中規模） | RDS PostgreSQL | コスト重視、運用が簡単 |
| OLTP（大規模・高可用性） | Aurora PostgreSQL | 高性能、自動フェイルオーバー |
| キーバリュー・高スループット | DynamoDB | シングルミリ秒レイテンシ、無限スケール |
| セッション・キャッシュ | ElastiCache (Redis) | インメモリ、低レイテンシ |

## IaC 生成形式

### Terraform（推奨）

既存の `aws-infrastructure` スキル（`/aws-infra`）に委譲する。Terraform コード生成後は `aws-infra-review-agent` で検証する。

### CDK（TypeScript）

```
cdk/
├── bin/
│   └── app.ts              # エントリポイント
├── lib/
│   ├── network-stack.ts     # VPC, サブネット
│   ├── database-stack.ts    # RDS / Aurora
│   ├── compute-stack.ts     # App Runner / ECS / Lambda
│   └── pipeline-stack.ts    # CodePipeline
├── cdk.json
└── tsconfig.json
```

### CloudFormation

YAML テンプレートで生成する。ネストされたスタックでモジュール化する。

## 関連スキル・エージェント

| 名前 | 関係 |
|------|------|
| aws-infrastructure | Terraform 生成を委譲 |
| aws-serverless | サーバーレス構成の知識を参照 |
| aws-databases | DB 選定の知識を参照 |
| aws-infra-review-agent | 生成コードの検証 |
