#!/usr/bin/env bash
set -euo pipefail

# コンテナ名に PID を付与して並列実行・残留に強くする
CONTAINER_NAME="todo-test-pg-$$"
IMAGE="postgres:16-alpine"
# 既定は 15432（開発 DB の 5432 と衝突しないように）。TEST_DB_PORT で上書き可能。
PORT="${TEST_DB_PORT:-15432}"
DB_USER="todo"
DB_PASSWORD="todo"
DB_NAME="todo_test"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

trap cleanup EXIT

cleanup

docker run -d \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_USER="$DB_USER" \
  -e POSTGRES_PASSWORD="$DB_PASSWORD" \
  -e POSTGRES_DB="$DB_NAME" \
  -p "${PORT}:5432" \
  "$IMAGE" >/dev/null

for i in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "PostgreSQL did not become ready in time" >&2
    exit 1
  fi

  sleep 1
done

export TEST_DATABASE_URL="postgresql://todo:todo@localhost:${PORT}/todo_test?schema=public"

status=0
npx vitest run "$@" || status=$?
exit "$status"
