# 再開メモ: Issue #21（2026-07-10 セッション終了時点）

## このセッション全体の到達点
- gcloud / terraform / codex CLI 導入済み（`~/google-cloud-sdk`, `~/bin/terraform`, nvm codex）。GCP 認証は `gcloud auth login` 済み（ADC 未設定 → terraform は `GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)` を使う）。
- Week 8: PR #19 マージ済み → その後 `terraform destroy` 済み。**GCP リソースは現在 0 個（課金なし）**。
- Week 9: Issue #20/#21/#22 起票済み。
  - **#20（Prisma → PostgreSQL）: PR #23 マージ済み・完了**。
  - **#21（インフラ拡張）: 実装中（本メモの対象）**。
  - #22（デプロイ&到達確認）: 未着手。

## #21 の現在地（worktree: .claude/worktrees/21-gcp-infra, branch feature/21-gcp-infra）
- Phase A: plan.md / todos.md 承認済み（決定: **Bastion 削除** / **Secret 枠のみ+GUI投入・password_wo**）。
- Phase B: codex-implement 完了（terraform 全面改修、fmt/validate 通過）。`terraform plan` 成功（**31 add**、Direct VPC egress・password_wo write-only・ci/cd トリガー確認）。
- レビュー: gcp-infra-review-agent・codex-review とも**完了**（両者とも Request Changes）。指摘は下記に統合済み。
- **変更は未コミット**（worktree に残置）。

## 次回やること（順番）
1. **レビュー指摘の反映**（gcp-infra-review-agent より。codex-review 結果も統合）:
   - `versions.tf`: `required_version` を `>= 1.11` に（password_wo 要件, F2）
   - `iam.tf`: プロジェクト全体の `iam.serviceAccountUser` 付与（`cloud_build_service_account_user`）を削除しリソーススコープ actAs だけ残す（S1）。`run.admin`→`run.developer`（I3）。Cloud Build サービスエージェントに build SA への `roles/iam.serviceAccountTokenCreator` を付与（`google_project_service_identity` 追加, I1）
   - `cloudbuild.tf`: CI ステップの `npm test`（postgres 必須で赤化）を `npm ci && npm run build`（+ `npx tsc --noEmit`）等 DB 非依存に変更（I4）
   - `cloudbuild.yaml`: `gcloud run deploy` に `--quiet` 追加、region 明示、command 依存を明記（I2）
   - `network.tf`: PSA `prefix_length` 16→24（I5, 任意）
   - `README`/tfvars 例: **二段階 apply**（secret + SQL を先に apply → `gcloud secrets versions add todo-database-url` で接続文字列を投入 → 全体 apply）を明記（F1・初回 Cloud Run 起動失敗回避）。TF≥1.11 前提、GitHub App 手動接続、DB パスワードは `secrets.auto.tfvars`（gitignore 済）経由で渡す旨も明記。

   **codex-review の追加指摘（gcp-infra-review と統合して対応）:**
   - `compute.tf`: F1 の深掘り。プレースホルダ image `cloudrun/container/hello` は distroless で `sh`/`node` 無し。ここに migrate の `command` 上書きを載せると初回リビジョンが即クラッシュする。→ **初回リビジョンは `command` 上書きを付けない**（CD が実イメージへ差し替え後も env/command はマージ保持される）か、初期 image を実行可能なものにする。
   - `cloudbuild.tf`（CI/DB, Must#3）: `ci-*` の `npm test` は postgres 必須。対応案は2択 — (a) build 内で `postgres:16-alpine` を background step（`waitFor: ['-']`）起動し `TEST_DATABASE_URL` を渡す、(b) CI 専用 build config（`scripts/test-with-postgres.sh` 相当）に分離。※単純に `npm run build`+`tsc` に落とす案（gcp-infra-review I4）でも可。どれにするか要判断。
   - `iam.tf`（最小権限, Should）: run SA の `secretmanager.secretAccessor` を**プロジェクト全体→secret 単位**（`google_secret_manager_secret_iam_member`）に。Direct VPC egress + パスワード認証では run SA の `cloudsql.client` は**不要**なので削除可。`artifactregistry.writer` は repository 単位に絞る検討。
   - `database.tf`（保守性）: `password_wo_version` を変数化（ローテーション時に増分）。
   - Nit: `cloudbuild.yaml` 末尾 `images:` は push step と重複で冗長（削除可、push step は残す）。`allUsers` invoker を `allow_unauthenticated` 変数化＋意図コメント、`ingress` 明示。`outputs.database_url_template` に `sensitive = true` 検討。`.terraform.lock.hcl` のコミット方針を決める（現状 gitignore で再現性が担保されない）。
   - ドキュメントドリフト: `plan.md` の「2nd-gen connection」記述を実装（1st-gen `github{}`）に合わせて修正。
2. 再 `validate` + `plan`（token + DB パスワード変数を指定）で green 確認。
3. `/create-pr` 相当で commit（feat(infra): ...）→ changes.md → push → PR（Closes #21）。ユーザー承認後に push。
4. マージ後: 掃除（main FF・worktree/branch 削除）。**#21 は plan のみ**なので state 退避は不要。
5. **#22 へ**: `/start-issue #22`。ここで初めて実 apply（二段階）+ GitHub App 接続 + `cd-*` タグ push でデプロイ + ブラウザ到達確認。

## 注意
- #21 の実 apply は #22 で行う（本 Issue は Terraform 定義まで）。apply 時 F1 の二段階手順に従う。
- DB パスワードの実値はコミットしない（`secrets.auto.tfvars`）。
