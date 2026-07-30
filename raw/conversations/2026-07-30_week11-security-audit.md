# Week 11 宿題: TODO アプリの 4 層セキュリティ監査

- date: 2026-07-30
- topic: フロントエンド・API・DB・インフラの手動監査 + /security-audit による AI 監査

## 実施内容

Week 11 宿題の指示に従い、4 層を手動で監査したのち `/security-audit`（依存関係スキャン・シークレット検出）を実行した。

### フロントエンド層

| 項目 | 結果 | 根拠 |
|------|------|------|
| CSP | ✗ 未設定 | `next.config.ts` に `headers()` なし |
| X-Content-Type-Options | ✗ 未設定 | 同上 |
| HSTS | ✗ 未設定 | 同上（Cloud Run が TLS 終端するためヘッダー付与はアプリ責務） |
| innerHTML 直書き | ✓ なし | `dangerouslySetInnerHTML` / `innerHTML` の使用ゼロ。React の自動エスケープのみ |
| セッション cookie 属性 | △ | `httpOnly` / `secure`(本番) / `sameSite: 'lax'`（`lib/auth/session.ts:34-40`）。security skill の方針は `SameSite=Strict` |
| Server Actions allowedOrigins | △ | `next.config.ts:12-16` に `localhost:8080` と run.app ホストを許可。到達確認用と明記されているが CSRF 保護の緩和なので確認完了後に削除したい |

### API 層（Server Actions 構成）

| 項目 | 結果 | 根拠 |
|------|------|------|
| zod バリデーション | ✓ 全アクション | `TitleSchema`(max 255) / `NameSchema`(max 50) / `DirectionSchema` / `SignupSchema` / `LoginSchema` |
| 認可 | ✓ 多層防御 | middleware のリダイレクトに加え、全アクション冒頭で `getSession()` を再検証 |
| 所有者チェック | ✓ | `where: { id, userId }` の複合条件で他ユーザーのリソースに到達しない（todos.ts / categories.ts 全域） |
| 生 SQL | ✓ なし | `$queryRaw` は `app/api/health/route.ts:12` の定数 `SELECT 1` のみ（タグ付きテンプレート・ユーザー入力なし） |
| タイミング攻撃対策 | ✓ | login で DUMMY_HASH による一定時間比較（`auth.ts:24`） |
| セッション ID 生成 | ✗ | Prisma `@default(cuid())` を流用。CSPRNG 由来 128bit+ のトークンではない |
| password 長上限 | △ | `SignupSchema` は `min(8)` のみ。bcrypt は 72 バイト切り詰め、長大入力は CPU コスト。`max(72)` を追加したい |
| レート制限 | ✗ なし | login/signup のブルートフォース対策なし。現状は Cloud Run invoker 認証で露出が限定されており実質リスク低 |
| 期限切れセッション | △ | 読み取り時に無効化はされるが削除ジョブなし（衛生上の課題） |

### DB 層

| 項目 | 結果 | 根拠 |
|------|------|------|
| app / 読み取り専用 / migration の権限分離 | ✗ なし | DB ユーザーは `todo_app` 1 つ（`terraform/database.tf:63-70`）。`Dockerfile:53` の CMD で起動時に同一ユーザーが `prisma migrate deploy`（DDL）を実行 |
| GRANT 文の最小化 | ✗ なし | GRANT / CREATE ROLE はリポジトリ内に存在しない。Cloud SQL 作成ユーザーは cloudsqlsuperuser 相当の広い権限を持つ |
| スキーマ制約 | ✓ | FK + onDelete、`@@unique([userId, position])`、FK カラムへの明示インデックス |

### インフラ層

| 項目 | 結果 | 根拠 |
|------|------|------|
| DB Public IP 無効化 | ✓ | `ipv4_enabled = false`、Private IP + PSA のみ（`database.tf:40-44`） |
| IAM / Role 最小権限 | ✓（制約付き妥協あり） | ワークロード別 SA（run / build）。secretAccessor と artifactregistry.writer はプロジェクト単位（非オーナーのため secret / repository 単位の setIamPolicy 不可、iam.tf にコメントで明記） |
| Secret Manager | ✓ | DATABASE_URL を Secret Manager 経由で注入（`compute.tf:40-48`）。`password_wo` で state に平文を残さない |
| tfstate / tfvars | △ | tfstate・`*.auto.tfvars` は gitignore 済み（gitleaks 26 commits リーク 0）。ただし state はローカル管理で、skill 方針のリモートバックエンド（GCS + ロック）未対応 |
| 削除保護 | 許容 | `deletion_protection = false`（学習用と明記。本番は true） |
| 公開範囲 | ✓ | Cloud Run invoker は特定ユーザーのみ（org ポリシーで allUsers 禁止） |

### AI 監査（/security-audit）

- `npm audit`: **high 4 件**
  - `next` 15.5.19 → 15.5.22 で修正される advisories 多数（Server Actions DoS、SSRF、cache confusion、Server Function endpoint の非認証開示等）。本アプリは App Router + Server Actions 構成のため該当
  - `postcss` / `sharp` の脆弱性は next 同梱の推移的依存。next のパッチ更新で解消
  - `brace-expansion`（DoS）は dev 依存の推移的。`npm audit fix` で解消可
- `gitleaks detect`: 26 commits スキャン、リークなし
- `.env` は gitignore 済み。追跡されているのは `.env.example` のみ

## 決定事項

- 監査結果は本ファイルに記録し、対策は Issue 化して個別に実施する（起票はユーザーが行う）
- 対策の優先順位は次のとおり
  1. **High**: next を 15.5.22 へパッチ更新 + `npm audit fix`（依存脆弱性）
  2. **High**: セキュリティヘッダー追加（CSP / X-Content-Type-Options / HSTS / X-Frame-Options / Referrer-Policy / Permissions-Policy）
  3. **High**: DB 権限分離。`todo_migrate`（DDL）と `todo_app`（DML のみ）を分離し GRANT を最小化、起動時 migrate を CMD から分離
  4. **Medium**: セッション ID を CSPRNG 生成（`crypto.randomBytes(32)` 相当）へ変更
  5. **Medium**: 認証エンドポイントのレート制限（公開範囲拡大の前提条件）
  6. **Low**: password `max(72)`、SameSite=Strict 検討、allowedOrigins の整理、tfstate のリモートバックエンド化

## 現在のプロジェクト状態

- Issue #22 まで完了（GCP デプロイ済み、Cloud Run + Cloud SQL Private IP 構成）
- API 層の多層防御（zod + セッション再検証 + 所有者チェック）は全アクションで実装済み
- 4 層のうち DB 層の権限分離とフロントエンドのセキュリティヘッダーが未着手領域

## 未解決事項

- wiki/ 層（`wiki/pages/security/` など）が本リポジトリに未整備。doc-management ルール上は wiki への蒸留先が必要だが、今回は raw への記録のみ。wiki 骨格の整備は別課題
- 対策 Issue の起票と実施（上記優先順位 1〜3 が Week 12 発表までの候補）
