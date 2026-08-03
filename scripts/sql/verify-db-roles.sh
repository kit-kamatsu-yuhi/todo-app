#!/usr/bin/env bash
set -euo pipefail

# コンテナ名に PID を付与して並列実行・残留に強くする
CONTAINER_NAME="todo-verify-roles-pg-$$"
IMAGE="postgres:16-alpine"
# 既定は 15433（既存のテスト用 15432 と衝突しないように）。VERIFY_DB_PORT で上書き可能。
PORT="${VERIFY_DB_PORT:-15433}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SQL_FILE="$ROOT_DIR/scripts/sql/setup-db-roles.sql"
PRISMA="$ROOT_DIR/node_modules/.bin/prisma"

DB_NAME="todo"
POSTGRES_PASSWORD="postgres_password"
APP_USER="todo_app"
APP_PASSWORD="todo_app_password"
MIGRATE_USER="todo_migrate"
MIGRATE_PASSWORD="todo_migrate_password"

TMP_DIR=""

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

if [ ! -x "$PRISMA" ]; then
  echo "Prisma CLI が見つかりません。先に node_modules を用意してください。" >&2
  exit 1
fi

if [ ! -f "$SQL_FILE" ]; then
  echo "setup SQL が見つかりません: $SQL_FILE" >&2
  exit 1
fi

cleanup

docker run -d \
  --name "$CONTAINER_NAME" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -p "${PORT}:5432" \
  "$IMAGE" >/dev/null

for i in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
    break
  fi

  if [ "$i" -eq 30 ]; then
    echo "PostgreSQL が起動しませんでした" >&2
    exit 1
  fi

  sleep 1
done

run_psql() {
  local user="$1"
  local db="$2"
  shift 2

  docker exec -i "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U "$user" -d "$db" "$@"
}

APP_DATABASE_URL="postgresql://${APP_USER}:${APP_PASSWORD}@localhost:${PORT}/${DB_NAME}?schema=public"
MIGRATE_DATABASE_URL="postgresql://${MIGRATE_USER}:${MIGRATE_PASSWORD}@localhost:${PORT}/${DB_NAME}?schema=public"

run_psql postgres postgres <<SQL
CREATE ROLE ${APP_USER} LOGIN PASSWORD '${APP_PASSWORD}';
CREATE ROLE ${MIGRATE_USER} LOGIN PASSWORD '${MIGRATE_PASSWORD}';
CREATE DATABASE ${DB_NAME};
SQL

run_psql postgres "$DB_NAME" <<SQL
GRANT USAGE, CREATE ON SCHEMA public TO ${APP_USER};
SQL

DATABASE_URL="$APP_DATABASE_URL" "$PRISMA" migrate deploy --schema "$ROOT_DIR/prisma/schema.prisma"

run_psql postgres "$DB_NAME" -f - < "$SQL_FILE"

failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

TMP_DIR="$(mktemp -d)"
mkdir -p "$TMP_DIR/prisma"
cp "$ROOT_DIR/prisma/schema.prisma" "$TMP_DIR/prisma/schema.prisma"
cp -R "$ROOT_DIR/prisma/migrations" "$TMP_DIR/prisma/migrations"
mkdir -p "$TMP_DIR/prisma/migrations/20990101000000_verify_default_privileges"
cat > "$TMP_DIR/prisma/migrations/20990101000000_verify_default_privileges/migration.sql" <<'SQL'
CREATE TABLE "VerifyDefaultPriv" ("id" TEXT NOT NULL, "note" TEXT, CONSTRAINT "VerifyDefaultPriv_pkey" PRIMARY KEY ("id"));
SQL

if DATABASE_URL="$MIGRATE_DATABASE_URL" "$PRISMA" migrate deploy --schema "$TMP_DIR/prisma/schema.prisma"; then
  pass "todo_migrate で prisma migrate deploy が成功する"
else
  fail "todo_migrate で prisma migrate deploy が成功する"
fi

if create_error="$(docker exec "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U "$APP_USER" -d "$DB_NAME" -c 'CREATE TABLE "ShouldFail" ("id" TEXT);' 2>&1)"; then
  fail "todo_app で public スキーマに CREATE TABLE できない"
else
  if [[ "$create_error" == *"permission denied for schema public"* ]]; then
    pass "todo_app で public スキーマに CREATE TABLE できない"
  else
    echo "$create_error" >&2
    fail "todo_app の CREATE TABLE 失敗理由が schema 権限不足である"
  fi
fi

# REASSIGN OWNED の回帰検知: 所有権が todo_migrate に移っていれば
# todo_app からの ALTER TABLE / DROP TABLE は所有者チェックで拒否される
ddl_denied=1
for ddl_stmt in 'ALTER TABLE "User" ADD COLUMN "should_fail" TEXT;' 'DROP TABLE "User";'; do
  if ddl_error="$(docker exec "$CONTAINER_NAME" psql -v ON_ERROR_STOP=1 -U "$APP_USER" -d "$DB_NAME" -c "$ddl_stmt" 2>&1)"; then
    echo "想定外に成功しました: $ddl_stmt" >&2
    ddl_denied=0
  elif [[ "$ddl_error" != *"must be owner of table"* && "$ddl_error" != *"permission denied"* ]]; then
    echo "$ddl_error" >&2
    ddl_denied=0
  fi
done

if [ "$ddl_denied" -eq 1 ]; then
  pass "todo_app で既存テーブルの ALTER TABLE / DROP TABLE ができない"
else
  fail "todo_app で既存テーブルの ALTER TABLE / DROP TABLE ができない"
fi

if run_psql "$APP_USER" "$DB_NAME" <<'SQL'
INSERT INTO "User" ("id", "email", "passwordHash")
VALUES ('verify-user', 'verify@example.com', 'hash');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "User"
    WHERE "id" = 'verify-user' AND "email" = 'verify@example.com'
  ) THEN
    RAISE EXCEPTION 'User INSERT/SELECT failed';
  END IF;
END
$$;

UPDATE "User"
SET "passwordHash" = 'hash-updated'
WHERE "id" = 'verify-user';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "User"
    WHERE "id" = 'verify-user' AND "passwordHash" = 'hash-updated'
  ) THEN
    RAISE EXCEPTION 'User UPDATE failed';
  END IF;
END
$$;

DELETE FROM "User"
WHERE "id" = 'verify-user';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "User" WHERE "id" = 'verify-user') THEN
    RAISE EXCEPTION 'User DELETE failed';
  END IF;
END
$$;
SQL
then
  pass "todo_app で既存 User テーブルの INSERT/SELECT/UPDATE/DELETE が成功する"
else
  fail "todo_app で既存 User テーブルの INSERT/SELECT/UPDATE/DELETE が成功する"
fi

if run_psql "$APP_USER" "$DB_NAME" <<'SQL'
INSERT INTO "VerifyDefaultPriv" ("id", "note")
VALUES ('verify-default-priv', 'created by migration');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "VerifyDefaultPriv"
    WHERE "id" = 'verify-default-priv' AND "note" = 'created by migration'
  ) THEN
    RAISE EXCEPTION 'VerifyDefaultPriv INSERT/SELECT failed';
  END IF;
END
$$;

UPDATE "VerifyDefaultPriv"
SET "note" = 'updated by app role'
WHERE "id" = 'verify-default-priv';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM "VerifyDefaultPriv"
    WHERE "id" = 'verify-default-priv' AND "note" = 'updated by app role'
  ) THEN
    RAISE EXCEPTION 'VerifyDefaultPriv UPDATE failed';
  END IF;
END
$$;

DELETE FROM "VerifyDefaultPriv"
WHERE "id" = 'verify-default-priv';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM "VerifyDefaultPriv" WHERE "id" = 'verify-default-priv') THEN
    RAISE EXCEPTION 'VerifyDefaultPriv DELETE failed';
  END IF;
END
$$;
SQL
then
  pass "todo_app で新規 VerifyDefaultPriv テーブルの INSERT/SELECT/UPDATE/DELETE が成功する"
else
  fail "todo_app で新規 VerifyDefaultPriv テーブルの INSERT/SELECT/UPDATE/DELETE が成功する"
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "ALL PASS"
