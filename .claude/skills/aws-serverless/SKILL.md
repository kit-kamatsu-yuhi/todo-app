---
name: aws-serverless
description: AWS サーバーレス設計知識（Lambda・API Gateway・Step Functions・SAM/CDK パターン）
user_invocable: false
---

# AWS Serverless

awslabs/agent-plugins の aws-serverless 知識に基づくサーバーレス設計スキル。

## 対象サービス

| サービス | 用途 | 選定基準 |
|---------|------|---------|
| Lambda | イベント駆動の関数実行 | 短時間処理（最大15分）、ミリ秒課金 |
| API Gateway (REST) | REST API エンドポイント | Lambda との統合、認証・スロットリング |
| API Gateway (HTTP) | HTTP API エンドポイント | REST より低コスト、シンプルなユースケース |
| Step Functions | ワークフローオーケストレーション | 複数 Lambda の連携、エラーハンドリング |
| EventBridge | イベントバス | サービス間の疎結合連携 |
| SQS | メッセージキュー | 非同期処理、バッファリング |
| SNS | 通知 | Pub/Sub、メール・SMS 配信 |

## Lambda 設計パターン

### 単一責任パターン

1つの Lambda 関数は1つの責務を持つ。

```
POST /api/todos → createTodo Lambda
GET  /api/todos → listTodos Lambda
```

### ファットLambda パターン

1つの Lambda で複数エンドポイントを処理する。Express / Hono 等の Web フレームワークを使う。

```
/api/* → todoApi Lambda（内部でルーティング）
```

小規模アプリではファット Lambda が管理しやすい。規模が大きくなったら分割する。

## Lambda のベストプラクティス

- **コールドスタート対策**: Provisioned Concurrency または SnapStart（Java）を検討する
- **レイヤー**: 共通ライブラリは Lambda Layer に分離する
- **環境変数**: シークレットは Secrets Manager 経由で取得する（ハードコード禁止）
- **タイムアウト**: デフォルト3秒は短すぎる。API は10〜30秒、バッチは5〜15分に設定する
- **メモリ**: メモリを増やすと CPU も比例して割り当てられる。コスト最適化は AWS Lambda Power Tuning で測定する
- **べき等性**: リトライ時に副作用が重複しないよう設計する

## SAM / CDK の使い分け

| ツール | 特徴 | 推奨ケース |
|-------|------|-----------|
| SAM | サーバーレス特化。`template.yaml` 1ファイルで定義 | Lambda + API GW のシンプル構成 |
| CDK | 汎用 IaC。TypeScript/Python でプログラマブルに記述 | 複雑な構成、他サービスとの統合 |

詳細は `references/sam-cdk-guide.md` を参照。

## 関連スキル

| 名前 | 関係 |
|------|------|
| aws-deploy | デプロイワークフローから参照 |
| aws-databases | DynamoDB の設計知識 |
