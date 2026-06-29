# トラブルシューティング

## IAP トンネルが接続できない

### 症状

```
ERROR: (gcloud.compute.start-iap-tunnel) Error while connecting [4003: 'failed to connect to backend'].
```

### 原因と対策

| 原因 | 対策 |
|------|------|
| IAP 権限不足 | `roles/iap.tunnelResourceAccessor` をユーザーに付与する |
| ファイアウォール未設定 | `35.235.240.0/20` からの TCP:22 を許可する |
| Bastion VM が停止中 | `gcloud compute instances start INSTANCE --project=PROJECT --zone=ZONE` |
| IAP API 未有効化 | `gcloud services enable iap.googleapis.com --project=PROJECT` |

### 確認コマンド

```bash
# IAP 権限の確認
gcloud projects get-iam-policy PROJECT \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/iap.tunnelResourceAccessor"

# ファイアウォールルールの確認
gcloud compute firewall-rules list --project=PROJECT \
  --filter="sourceRanges:35.235.240.0/20"
```

## socat が起動しない

### 症状

スクリプト実行時に `socat 準備チェック` が最大リトライ回数に達して失敗する。

### 原因と対策

| 原因 | 対策 |
|------|------|
| startup script 未完了 | VM 起動後しばらく待つ（最大2分程度） |
| socat 未インストール | startup script に `apt-get install -y socat` が含まれているか確認 |
| Cloud SQL の Private IP 解決不可 | VPC ピアリングが正しく設定されているか確認 |
| startup script のエラー | VM に SSH して `sudo journalctl -u google-startup-scripts.service` を確認 |

### 確認コマンド

```bash
# Bastion VM に SSH で接続
gcloud compute ssh INSTANCE --project=PROJECT --zone=ZONE --tunnel-through-iap

# startup script のログ確認
sudo journalctl -u google-startup-scripts.service

# socat プロセスの確認
ps aux | grep socat

# ポートリッスンの確認
ss -tln | grep :5432
```

## ポート競合

### 症状

```
ERROR: (gcloud.compute.start-iap-tunnel) Local port [15432] is not available.
```

### 対策

別のローカルポートを指定する:

```bash
# スクリプト引数で指定
./iap-bastion-connect.sh --local-port 25432

# 環境変数で指定
LOCAL_PORT=25432 ./iap-bastion-connect.sh
```

使用中のポートを確認する:

```bash
lsof -i :15432
```

## psql で接続できない

### 症状

```
psql: error: connection to server at "localhost" (127.0.0.1), port 15432 failed: Connection refused
```

### 原因と対策

| 原因 | 対策 |
|------|------|
| トンネル未確立 | スクリプトの「トンネルを起動します」メッセージを確認する |
| DB ユーザー/パスワードの誤り | Secret Manager からパスワードを再取得する |
| DB が存在しない | `\l` でデータベース一覧を確認する |
| Cloud SQL が停止中 | GCP Console で Cloud SQL インスタンスの状態を確認する |

### パスワードの取得

```bash
gcloud secrets versions access latest --secret=SECRET_NAME --project=PROJECT
```

## Bastion VM が停止しない

### 症状

スクリプトを `Ctrl+C` で停止したが、Bastion VM が動き続けている。

### 対策

手動で停止する:

```bash
gcloud compute instances stop INSTANCE --project=PROJECT --zone=ZONE
```

VM の状態を確認する:

```bash
gcloud compute instances describe INSTANCE --project=PROJECT --zone=ZONE \
  --format="value(status)"
```
