-- Issue #28: DB ユーザーの権限分離セットアップ
--
-- 実行者: postgres（Cloud SQL の cloudsqlsuperuser メンバー）
-- 実行タイミング: terraform apply と Secret 投入の後に 1 回だけ
-- 実行方法: db-connect（IAP + Bastion）の psql 経由で対象 DB に接続し `psql -v ON_ERROR_STOP=1 -f` で実行
-- 資格情報は含めない（ロール名のみ）
--
-- 注意: Cloud SQL Admin API 経由でユーザーを更新（パスワード変更等）すると
-- cloudsqlsuperuser の membership が再付与され得る。その際は本 SQL を再実行する
-- （全ステップ冪等のため再実行しても安全）。

BEGIN;

-- 1. Cloud SQL では REASSIGN に両ロールへの membership が必要
GRANT todo_app TO "postgres";
GRANT todo_migrate TO "postgres";

-- 2. 既存テーブル・_prisma_migrations を含む全オブジェクトの所有権を todo_migrate に移転
REASSIGN OWNED BY todo_app TO todo_migrate;

-- 2b. public スキーマの所有権を todo_migrate に揃える
--     （PG15+ の Cloud SQL では public の owner が cloudsqlsuperuser のため
--       REASSIGN では移らない。owner の暗黙 CREATE を DDL ロールに限定する）
ALTER SCHEMA public OWNER TO todo_migrate;

-- 3. アプリ用ロールから public スキーマへの CREATE 権限を取り除く
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM todo_app;

-- 3b. Cloud SQL では todo_app も cloudsqlsuperuser メンバーとして作成されるため
--     membership を剥奪して継承権限（public への CREATE 等）を断つ。
--     ローカル PostgreSQL には cloudsqlsuperuser が存在しないので no-op。
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'cloudsqlsuperuser') THEN
    EXECUTE 'REVOKE cloudsqlsuperuser FROM todo_app';
  END IF;
END
$$;

-- 4. アプリ用ロールは参照のみ、マイグレーション用ロールは作成を許可する
--    （todo_migrate は 2b で schema owner になるが、PUBLIC 既定や所有権に
--      依存させず明示 GRANT しておく）
GRANT USAGE ON SCHEMA public TO todo_app;
GRANT USAGE, CREATE ON SCHEMA public TO todo_migrate;

-- 5. 既存テーブルへの DML 権限をアプリ用ロールへ付与する
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO todo_app;

-- 6. 今後 todo_migrate が作成するテーブルへの DML 権限をアプリ用ロールへ自動付与する
ALTER DEFAULT PRIVILEGES FOR ROLE todo_migrate IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO todo_app;

-- 7. 既存・新規シーケンスの利用権限をアプリ用ロールへ付与する
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO todo_app;
ALTER DEFAULT PRIVILEGES FOR ROLE todo_migrate IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO todo_app;

COMMIT;
