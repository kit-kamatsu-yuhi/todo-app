---
name: db-connect
description: GCP の IAP トンネル + Bastion VM 経由で Cloud SQL に接続する手順を案内し、接続スクリプトを生成する
user_invocable: true
command: /db-connect
---

# DB Connect

IAP トンネル + Bastion VM 経由で Cloud SQL（Private IP）に安全に接続するスキル。
プロジェクト固有のパラメータをヒアリングし、カスタマイズ済みの接続スクリプトを生成する。

## 前提条件

| 項目 | 要件 |
|------|------|
| gcloud CLI | インストール済み・認証済み（`gcloud auth login`） |
| IAP 権限 | `roles/iap.tunnelResourceAccessor` が付与されている |
| Bastion VM | Compute Engine に踏み台 VM が構築済み |
| Cloud SQL | Private IP で構成済み |
| socat | Bastion VM の startup script で socat が起動する構成 |

## セキュリティ要件

| 項目 | 要件 |
|------|------|
| DB アクセス経路 | Private IP のみ。Public IP 禁止 |
| 認証 | IAP 経由の SSH トンネル（Google アカウント認証） |
| Bastion VM | 使用時のみ起動、使用後は自動停止 |
| IAM | `bastion-sa` に `roles/cloudsql.client` のみ（最小権限） |
| シークレット | DB パスワードは Secret Manager から取得 |
| ファイアウォール | SSH は IAP 経由のみ（`35.235.240.0/20`） |

## 対話フロー

### 1. パラメータのヒアリング

以下をユーザーに確認する:

| パラメータ | 説明 | デフォルト |
|-----------|------|-----------|
| `PROJECT` | GCP プロジェクト ID | （必須） |
| `ZONE` | Bastion VM のゾーン | `asia-northeast1-a` |
| `INSTANCE` | Bastion VM のインスタンス名 | （必須） |
| `LOCAL_PORT` | ローカルのリッスンポート | `15432` |
| `DB_PORT` | Cloud SQL のポート | `5432` |
| `DB_NAME` | データベース名 | （必須） |
| `DB_USER` | データベースユーザー名 | （必須） |
| `SECRET_NAME` | Secret Manager のシークレット名 | `db-password` |

### 2. インフラ未構築の場合

Bastion VM や Cloud SQL がまだ構築されていない場合は、以下を案内する:

- `/gcp-infra` で Bastion VM・VPC・Cloud SQL・IAP を一括構築できる
- `references/bastion-terraform-example.tf` を Terraform サンプルとして提示する

### 3. 接続スクリプトの生成

`references/iap-bastion-connect.sh` をベースに、ヒアリングした値で変数を埋めたスクリプトを生成する。

### 4. 接続手順の案内

1. 生成したスクリプトをローカルに保存する
2. `chmod +x` で実行権限を付与する
3. スクリプトを実行する（Bastion VM の起動 → socat 待機 → IAP トンネル開設）
4. 別ターミナルから `psql` 等で `localhost:LOCAL_PORT` に接続する
5. `Ctrl+C` でトンネルを終了する（Bastion VM は自動停止）

## 関連スキル・エージェント

### インフラ構築

| スキル/エージェント | コマンド | 用途 |
|-------------------|---------|------|
| gcp-infrastructure | `/gcp-infra` | Bastion VM・VPC・Cloud SQL・IAP の Terraform コード生成 |
| gcp-infra-review-agent | （自動） | 生成した Terraform コードのセキュリティ・コスト・可用性を検証 |

### レビュー・検証

| スキル/エージェント | コマンド | 用途 |
|-------------------|---------|------|
| gcp-infra-review-agent | （サブエージェント） | Terraform の IAM 最小権限・ネットワーク分離・DB 削除保護を検証 |
| review | `/review` | db-connect スキル自体のコードレビュー |
| security-audit | `/security-audit` | スクリプト内のセキュリティ脆弱性を検出 |
| review-agent | （サブエージェント） | PR 作成時の多角的コードレビュー |

## 使い方

```
/db-connect
```
