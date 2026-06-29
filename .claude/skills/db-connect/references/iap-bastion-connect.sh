#!/usr/bin/env bash
set -euo pipefail

#
# IAP Tunnel + Bastion VM 経由で Cloud SQL に接続するスクリプト
#
# 使い方:
#   ./iap-bastion-connect.sh
#   ./iap-bastion-connect.sh --local-port 25432
#
# 環境変数で設定を上書き可能:
#   PROJECT=my-project ZONE=us-central1-a ./iap-bastion-connect.sh
#

# === 設定（環境変数で上書き可能） ===
PROJECT="${PROJECT:?ERROR: PROJECT 環境変数を設定してください（例: PROJECT=my-project）}"
ZONE="${ZONE:-asia-northeast1-a}"
INSTANCE="${INSTANCE:?ERROR: INSTANCE 環境変数を設定してください（例: INSTANCE=bastion-vm）}"
LOCAL_PORT="${LOCAL_PORT:-15432}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:?ERROR: DB_NAME 環境変数を設定してください（例: DB_NAME=mydb）}"
DB_USER="${DB_USER:?ERROR: DB_USER 環境変数を設定してください（例: DB_USER=app）}"
SECRET_NAME="${SECRET_NAME:-db-password}"

# === 引数パース ===
while [[ $# -gt 0 ]]; do
  case $1 in
    --local-port)
      LOCAL_PORT="$2"
      shift 2
      ;;
    --db-port)
      DB_PORT="$2"
      shift 2
      ;;
    --help|-h)
      echo "使い方: $0 [OPTIONS]"
      echo ""
      echo "環境変数（必須）:"
      echo "  PROJECT       GCP プロジェクト ID"
      echo "  INSTANCE      Bastion VM のインスタンス名"
      echo "  DB_NAME       データベース名"
      echo "  DB_USER       データベースユーザー名"
      echo ""
      echo "環境変数（任意）:"
      echo "  ZONE          Bastion VM のゾーン (default: asia-northeast1-a)"
      echo "  LOCAL_PORT    ローカルポート (default: 15432)"
      echo "  DB_PORT       Cloud SQL ポート (default: 5432)"
      echo "  SECRET_NAME   Secret Manager のシークレット名 (default: db-password)"
      echo ""
      echo "オプション:"
      echo "  --local-port PORT   ローカルポートを指定"
      echo "  --db-port PORT      Cloud SQL ポートを指定"
      echo "  -h, --help          このヘルプを表示"
      exit 0
      ;;
    *)
      echo "ERROR: 不明なオプション: $1"
      exit 1
      ;;
  esac
done

# === 前提チェック ===
if ! command -v gcloud &>/dev/null; then
  echo "ERROR: gcloud CLI がインストールされていません"
  echo "  https://cloud.google.com/sdk/docs/install"
  exit 1
fi

# === クリーンアップ ===
cleanup() {
  echo ""
  echo "Bastion VM を停止します..."
  if gcloud compute instances stop "$INSTANCE" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --quiet 2>/dev/null; then
    echo "Bastion VM を停止しました"
  else
    echo "WARNING: Bastion VM の停止に失敗しました。手動で停止してください:"
    echo "  gcloud compute instances stop $INSTANCE --project=$PROJECT --zone=$ZONE"
  fi
}
trap cleanup EXIT

# === メイン処理 ===
echo "=== IAP Tunnel: localhost:${LOCAL_PORT} -> Bastion -> Cloud SQL ==="
echo ""
echo "Bastion VM を起動します..."
gcloud compute instances start "$INSTANCE" \
  --project="$PROJECT" \
  --zone="$ZONE"
echo "Bastion VM が起動しました。startup script の完了を待ちます..."

MAX_RETRIES=12
RETRY_INTERVAL=10
for i in $(seq 1 "$MAX_RETRIES"); do
  echo "  socat 準備チェック ($i/$MAX_RETRIES)..."
  if gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --tunnel-through-iap \
    --command="ss -tln | grep -q :${DB_PORT}" 2>/dev/null; then
    echo "  socat が起動しました"
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "ERROR: socat が起動しませんでした（${MAX_RETRIES}回リトライ済み）"
    echo ""
    echo "トラブルシューティング:"
    echo "  1. Bastion VM に SSH で接続して startup script のログを確認:"
    echo "     gcloud compute ssh $INSTANCE --project=$PROJECT --zone=$ZONE --tunnel-through-iap"
    echo "     sudo journalctl -u google-startup-scripts.service"
    echo "  2. socat がインストールされているか確認:"
    echo "     which socat"
    exit 1
  fi
  sleep "$RETRY_INTERVAL"
done

echo ""
echo "接続コマンド（別ターミナルで実行）:"
echo "  psql -h localhost -p ${LOCAL_PORT} -U ${DB_USER} -d ${DB_NAME}"
echo ""
echo "パスワード取得:"
echo "  gcloud secrets versions access latest --secret=${SECRET_NAME} --project=${PROJECT}"
echo ""
echo "トンネルを起動します... (Ctrl+C で停止 → Bastion VM も自動停止)"
echo ""

gcloud compute start-iap-tunnel "$INSTANCE" "$DB_PORT" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --local-host-port="localhost:${LOCAL_PORT}"
