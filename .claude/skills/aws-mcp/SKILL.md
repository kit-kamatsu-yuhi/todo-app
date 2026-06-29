---
name: aws-mcp
description: AWS MCP サーバーの有効化・無効化を切り替える
user_invocable: true
command: /aws-mcp
---

# AWS MCP

AWS Agent Plugins の MCP サーバーを有効化・無効化するスキル。

MCP サーバーは初期状態で無効。AWS クレデンシャルが必要なため、受講者の環境に応じてオプションで有効化する。MCP が無効でも、aws-deploy / aws-serverless / aws-databases スキルの知識で基本機能は動作する。

## 使い方

```
/aws-mcp enable    # MCP サーバーを有効化する
/aws-mcp disable   # MCP サーバーを無効化する
```

## enable 時の動作

1. `.claude/settings.json` の `mcpServers` セクションに AWS MCP 設定を追加する
2. `references/mcp-config.json` の内容をマージする
3. セッション再起動を案内する（MCP 設定はセッション開始時に読み込まれるため）

### 追加される MCP サーバー

| サーバー名 | パッケージ | 機能 |
|-----------|-----------|------|
| aws-deploy | awslabs.deploy-on-aws-mcp | アーキテクチャ推奨・IaC 生成 |
| aws-cost-analysis | awslabs.cost-analysis-mcp | コスト見積もり・最適化提案 |

## disable 時の動作

1. `.claude/settings.json` の `mcpServers` から `aws-deploy` と `aws-cost-analysis` を削除する
2. 他の MCP 設定は保持する

## 前提条件

- **AWS CLI** がインストールされていること
- **AWS プロファイル** が設定されていること（`aws configure` 済み）
- **uvx** が利用可能であること（`uv` パッケージマネージャー）

## MCP 無効時の代替

MCP が無効でも以下のスキルで AWS 知識を参照できる:

| スキル | 提供する知識 |
|-------|------------|
| aws-deploy | アーキテクチャ推奨、コスト概算、IaC パターン |
| aws-serverless | Lambda / API GW / Step Functions 設計 |
| aws-databases | DB サービス選定、DynamoDB 設計 |
| aws-infrastructure | Terraform 生成（`/aws-infra`） |

MCP はリアルタイムの料金情報取得やアカウント固有の推奨など、AWS API を直接呼ぶ機能を追加する。

## 実装手順（Claude Code への指示）

### enable

```
1. references/mcp-config.json を読む
2. .claude/settings.json を読む
3. settings.json の mcpServers に mcp-config.json の内容をマージする
   - mcpServers キーが存在しない場合は新規作成する
   - 既存の MCP 設定は保持する
4. settings.json を書き込む
5. 「AWS MCP を有効化しました。セッションを再起動してください。」と案内する
```

### disable

```
1. .claude/settings.json を読む
2. mcpServers から aws-deploy と aws-cost-analysis を削除する
3. mcpServers が空になった場合はキーごと削除する
4. settings.json を書き込む
5. 「AWS MCP を無効化しました。」と案内する
```
