# SAM / CDK ガイド

## SAM（Serverless Application Model）

### 基本構成

```yaml
# template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Globals:
  Function:
    Timeout: 30
    Runtime: nodejs20.x
    MemorySize: 256

Resources:
  TodoApi:
    Type: AWS::Serverless::Function
    Properties:
      Handler: index.handler
      CodeUri: src/
      Events:
        GetTodos:
          Type: Api
          Properties:
            Path: /api/todos
            Method: get
        CreateTodo:
          Type: Api
          Properties:
            Path: /api/todos
            Method: post
      Environment:
        Variables:
          TABLE_NAME: !Ref TodoTable

  TodoTable:
    Type: AWS::DynamoDB::Table
    Properties:
      TableName: todos
      AttributeDefinitions:
        - AttributeName: id
          AttributeType: S
      KeySchema:
        - AttributeName: id
          KeyType: HASH
      BillingMode: PAY_PER_REQUEST
```

### コマンド

```bash
sam init          # プロジェクト初期化
sam build         # ビルド
sam local start-api  # ローカル起動
sam deploy --guided  # デプロイ（初回）
sam deploy        # デプロイ（2回目以降）
```

## CDK（Cloud Development Kit）

### プロジェクト初期化

```bash
npx cdk init app --language typescript
```

### Lambda + API Gateway

```typescript
import * as cdk from 'aws-cdk-lib'
import * as lambda from 'aws-cdk-lib/aws-lambda-nodejs'
import * as apigw from 'aws-cdk-lib/aws-apigateway'

export class ApiStack extends cdk.Stack {
  constructor(scope: cdk.App, id: string) {
    super(scope, id)

    const handler = new lambda.NodejsFunction(this, 'TodoHandler', {
      entry: 'src/index.ts',
      handler: 'handler',
      runtime: cdk.aws_lambda.Runtime.NODEJS_20_X,
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
    })

    const api = new apigw.RestApi(this, 'TodoApi')
    const todos = api.root.addResource('api').addResource('todos')
    todos.addMethod('GET', new apigw.LambdaIntegration(handler))
    todos.addMethod('POST', new apigw.LambdaIntegration(handler))
  }
}
```

### コマンド

```bash
npx cdk synth     # CloudFormation テンプレート生成
npx cdk diff      # 差分確認
npx cdk deploy    # デプロイ
npx cdk destroy   # 削除
```

## SAM vs CDK 選定基準

| 観点 | SAM | CDK |
|------|-----|-----|
| 学習コスト | 低い（YAML 定義） | 中程度（TypeScript/Python） |
| サーバーレス特化 | 強い（組み込みサポート） | 汎用（明示的に定義） |
| ローカルテスト | `sam local` で簡単 | cdk-local または SAM と併用 |
| 複雑な構成 | 苦手（YAML が肥大化） | 得意（プログラマブル） |
| 非サーバーレスリソース | 可能だが冗長 | ネイティブサポート |
