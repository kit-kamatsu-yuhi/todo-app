# タスクリスト: Issue #20 Prisma を PostgreSQL へ移行

## 実装タスク
- [ ] schema.prisma の datasource provider を `postgresql` に変更（見積: 0.5h）
- [ ] docker-compose に開発/テスト用 `db`(postgres:16-alpine) サービスを追加、app の DATABASE_URL を postgres に変更（見積: 1h）
- [ ] `.env.example` を postgres 接続文字列のプレースホルダに更新（機密は入れない）（見積: 0.25h）
- [ ] 既存 SQLite マイグレーションを破棄し、postgres 向け init マイグレーションを再生成（見積: 1h）
- [ ] docker-compose の app 起動コマンド（migrate deploy）が postgres で動くことを確認（見積: 0.5h）
- [ ] 並び替え(position)の unique 制約が postgres で問題ないか確認し、必要ならトランザクション/一時オフセット対応（見積: 1.5h）

## テストタスク
- [ ] `tests/helpers/db.ts` を postgres 接続（TEST_DATABASE_URL）に変更、cleanDb を postgres 対応（見積: 1h）
- [ ] テスト実行前に postgres へ migrate deploy する仕組み（グローバルセットアップ）（見積: 1h）
- [ ] 既存テスト（auth / todos / categories / schema / health / page）を postgres で green 化（見積: 1.5h）
- [ ] 並び替えの制約に関する回帰テストを追加（見積: 0.5h）

## ドキュメントタスク
- [ ] README の DB 記述（sqlite → postgres、ローカル起動手順）更新
- [ ] `raw/issues/2026-07-10_20/` に plan.md / todos.md（本ファイル）/ changes.md（PR 時）を記録

## 受け入れ条件チェック
- [ ] postgres を指す DATABASE_URL でアプリ起動 → `/api/health` が `db:ok`
- [ ] 既存 CRUD（認証・Todo・カテゴリ・並び替え）が postgres で動作
- [ ] `npm test` が green
- [ ] 接続文字列がリポジトリにコミットされていない
