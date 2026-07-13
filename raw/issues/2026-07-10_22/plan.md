# 実装計画: Issue #22 タグデプロイ実行と到達確認

対象: https://github.com/kit-kamatsu-yuhi/todo-app/issues/22
worktree: `.claude/worktrees/22-deploy-verify`（branch `feature/22-deploy-verify`）
前提: #20（アプリ Postgres 化）・#21（インフラ定義）マージ済み。main の `terraform/` を使う。

本 Issue は「実デプロイ + 到達確認」の運用作業が主。コード変更は最小（不具合が出た時の修正のみ）。

## 受入基準
- `cd-*` タグ push → Cloud Build → Cloud Run 自動デプロイが成功する
- Cloud Run 上のアプリが Secret 経由の DB 接続で動作する
- 公開 Cloud Run URL にブラウザ（外部）から到達し画面表示される

## 役割分担（重要）

| ステップ | 実行者 | 理由 |
|---------|--------|------|
| gcloud 再認証 | **あなた**（素のターミナル） | 対話ログイン。トークン期限切れ |
| Cloud Build GitHub App 接続 | **あなた**（GCP Console） | OAuth 認可は TF 不可 |
| 実 `terraform apply`（課金発生）の承認 | **あなた** | 課金・不可逆の外向き操作 |
| plan ファイル生成 / apply 実行 / 検証 | 私（再認証後、あなたのトークンで） | 非対話で実行可能 |
| `cd-*` タグ作成・push | 私 or あなた | git 操作。実デプロイが走る点は承認済み前提 |

## 手順（Runbook）

### 0. 前提（あなた）
1. 再認証: `~/google-cloud-sdk/bin/gcloud auth login --no-launch-browser`（素のターミナル）
2. Cloud Build の GitHub App を `kit-kamatsu-yuhi/todo-app` に接続（GCP Console → Cloud Build → トリガー、または github.com/settings/installations）

### 1. 二段階 apply（#21 README 準拠）
- `secrets.auto.tfvars`（未コミット）に DB パスワードを用意（password_wo 経由で state 非保存）
- Stage 1: Secret 枠 + Cloud SQL を先に作成
  `terraform apply -target=google_secret_manager_secret.database_url -target=google_sql_database_instance.main -target=google_sql_database.app -target=google_sql_user.app`
- Stage 2: Private IP 確認 → `DATABASE_URL` を Secret に version 投入（`gcloud secrets versions add todo-database-url`）
- Stage 3: 全体 `terraform apply`（Cloud Run / Cloud Build / Artifact Registry / IAM）

### 2. 初回イメージのデプロイ（cd-* タグ）
- `cd-0.1.0` 等のタグを push → Cloud Build が実イメージをビルド → AR push → Cloud Run デプロイ
- Cloud Run 起動時に `prisma migrate deploy` が走り Cloud SQL にスキーマ適用

### 3. 到達確認
- `terraform output cloud_run_url` の URL にブラウザ（外部）からアクセス → トップページ表示
- サインアップ/ログイン → Todo 作成/並び替え/カテゴリが Secret 経由 DB で動作
- スクリーンショットを取得し `raw/` に記録

## リスク / 落とし穴
- 初回 apply は secret version 未投入だと Cloud Run 作成が失敗 → 二段階 apply 厳守
- GitHub App 未接続だと `cd-*` トリガーが発火しない → 接続を先に
- Cloud Build 実行時、service agent が build SA を actAs できないと失敗 → #21 で token creator 付与済み（apply 後に有効化を確認）
- Cloud Run 起動時 migrate が失敗するとリビジョン Ready にならない → ログ確認
- 課金: apply 後は Cloud SQL + Cloud Run（min0）。確認後 `terraform destroy` で撤去

## 実行フロー
1. ✅ 計画（本書）
2. ⬜ ユーザー承認 + 再認証 + GitHub App 接続
3. ⬜ 二段階 apply → cd-* デプロイ → 到達確認
4. ⬜ `raw/` に記録 → `/create-pr`（記録＋あれば修正）
5. ⬜ 確認後 `terraform destroy` で撤去（任意）
