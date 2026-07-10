#!/usr/bin/env bash
set -euo pipefail

#
# IAP トンネル + Bastion VM 経由で Cloud SQL(Private IP) に接続するスクリプト
#
# 前提:
#   - gcloud CLI インストール済み・認証済み（gcloud auth login）
#   - terraform apply 済み（Bastion VM / Cloud SQL / IAP 構築済み）
#   - ローカルに psql インストール済み
#
# 使い方:
#   ./connect-db.sh          # トンネルを開く（フォアグラウンド）
#   別ターミナルから psql で localhost:15432 に接続する（下記メッセージ参照）
#

# === 設定（環境変数で上書き可能） ===
PROJECT="${PROJECT:-aixeed-training-2026-07}"
ZONE="${ZONE:-asia-northeast1-a}"
INSTANCE="${INSTANCE:-todo-bastion}"
LOCAL_PORT="${LOCAL_PORT:-15432}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-todo}"
DB_USER="${DB_USER:-todo_app}"
SECRET_NAME="${SECRET_NAME:-todo-db-password}"

GCLOUD="${GCLOUD:-gcloud}"
if ! command -v "$GCLOUD" &>/dev/null; then
  if [ -x "$HOME/google-cloud-sdk/bin/gcloud" ]; then
    GCLOUD="$HOME/google-cloud-sdk/bin/gcloud"
  else
    echo "ERROR: gcloud が見つかりません" >&2
    exit 1
  fi
fi

# === クリーンアップ: 終了時に Bastion を停止 ===
cleanup() {
  echo ""
  echo "Bastion VM を停止します..."
  "$GCLOUD" compute instances stop "$INSTANCE" --project="$PROJECT" --zone="$ZONE" --quiet 2>/dev/null \
    && echo "停止しました" \
    || echo "WARNING: 停止に失敗。手動で: $GCLOUD compute instances stop $INSTANCE --zone=$ZONE"
}
trap cleanup EXIT

# === Bastion 起動 ===
echo "=== IAP Tunnel: localhost:${LOCAL_PORT} -> Bastion(${INSTANCE}) -> Cloud SQL:${DB_PORT} ==="
echo "Bastion VM を起動します..."
"$GCLOUD" compute instances start "$INSTANCE" --project="$PROJECT" --zone="$ZONE"

# === DB プロキシ(:5432)の起動待ち。IAP 経由 SSH で確認する（best-effort） ===
# socket-activated proxy なので待受はブート直後に立つ。SSH 確認は課題の
# 「IAP で SSH」デモも兼ねるが、SSH 権限が無くてもトンネルは開けるため
# 失敗しても警告のみで続行する。
echo "DB プロキシの起動を待ちます..."
MAX_RETRIES=9
ready=0
for i in $(seq 1 "$MAX_RETRIES"); do
  echo "  readiness check ($i/$MAX_RETRIES)..."
  if "$GCLOUD" compute ssh "$INSTANCE" \
    --project="$PROJECT" --zone="$ZONE" --tunnel-through-iap \
    --command="ss -tln | grep -q :${DB_PORT}" 2>/dev/null; then
    echo "  プロキシが :${DB_PORT} で待ち受け中（IAP SSH 疎通も確認）"
    ready=1
    break
  fi
  sleep 10
done
if [ "$ready" -ne 1 ]; then
  echo "WARNING: SSH での待受確認ができませんでした。トンネルは開きますが、"
  echo "  psql が繋がらない場合は Bastion の起動/startup script を確認してください:"
  echo "    $GCLOUD compute ssh $INSTANCE --project=$PROJECT --zone=$ZONE --tunnel-through-iap"
  echo "    systemctl status cloudsql-proxy.socket; sudo journalctl -u google-startup-scripts.service"
fi

# === 接続手順の案内 ===
cat <<MSG

トンネルを開きます。別ターミナルで以下を実行してください:

  # 1) DB パスワードを取得
  #    ローカル state から（Secret Manager 読取権限が無い環境はこちら）:
  #      (terraform ディレクトリで) terraform output -raw db_password
  #    権限がある場合は Secret Manager から:
  #      $GCLOUD secrets versions access latest --secret=${SECRET_NAME} --project=${PROJECT}

  # 2) psql で接続（パスワードはプロンプトに貼り付け）
  psql -h localhost -p ${LOCAL_PORT} -U ${DB_USER} -d ${DB_NAME}

  # 疎通だけ確認するなら（接続後に \\conninfo でも可）:
  psql "host=localhost port=${LOCAL_PORT} user=${DB_USER} dbname=${DB_NAME}" -c "SELECT version();"

Ctrl+C でトンネル終了 → Bastion 自動停止

MSG

# === IAP トンネル開設（フォアグラウンド） ===
# exec は使わない。Ctrl+C(SIGINT) でこのスクリプトに戻り、trap cleanup EXIT で
# Bastion を自動停止させるため。
"$GCLOUD" compute start-iap-tunnel "$INSTANCE" "$DB_PORT" \
  --project="$PROJECT" --zone="$ZONE" \
  --local-host-port="localhost:${LOCAL_PORT}"
