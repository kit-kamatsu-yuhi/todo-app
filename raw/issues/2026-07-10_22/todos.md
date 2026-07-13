# タスクリスト: Issue #22 タグデプロイ実行と到達確認

## 前提タスク（あなた）
- [ ] gcloud 再認証（`gcloud auth login --no-launch-browser`、素のターミナル）
- [ ] Cloud Build の GitHub App を `kit-kamatsu-yuhi/todo-app` に接続（GCP Console）
- [ ] 実 apply（課金発生）の承認

## デプロイタスク（再認証後、私が実行 / あなたと協調）
- [ ] `secrets.auto.tfvars` に DB パスワードを用意（未コミット・password_wo）
- [ ] Stage1: Secret 枠 + Cloud SQL を apply（plan ファイル生成 → apply）
- [ ] Private IP 取得 → `DATABASE_URL` を Secret に version 投入
- [ ] Stage3: 全体 apply（Cloud Run / Cloud Build / Artifact Registry / IAM）
- [ ] `cd-0.1.0` タグを push → Cloud Build → Cloud Run デプロイ確認

## 検証タスク
- [ ] `cd-*` で Cloud Build が走りデプロイ成功をログで確認
- [ ] Cloud Run URL にブラウザ（外部）から到達・画面表示
- [ ] サインアップ/ログイン/Todo/カテゴリが Secret 経由 DB で動作
- [ ] `ci-*` タグで CI（build+tsc）が走ることを確認
- [ ] スクリーンショット取得

## 記録・後処理
- [ ] `raw/issues/2026-07-10_22/` に動作確認記録・changes.md
- [ ] `/create-pr`（記録＋あれば修正）
- [ ] 確認後 `terraform destroy` で撤去（任意・課金停止）
