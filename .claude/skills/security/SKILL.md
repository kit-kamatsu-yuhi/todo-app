---
name: security
description: セキュリティスキル。セキュリティレビュー、脆弱性チェック、セキュアコーディングの依頼時に使用する。プロジェクト固有のセキュリティ方針・ツール選定を提供する。OWASP Top 10 の一般知識は既知とし、プロジェクト固有の適用方針に集中する。
---

# セキュリティ Skill

プロジェクト固有のセキュアコーディング方針。OWASP Top 10 の一般知識は省略する。

## セキュリティの 4 層モデル

Web アプリケーションのセキュリティは 4 層で多層防御する。

| 層 | 責務 | 突破されやすさ |
|----|------|---------------|
| フロントエンド | UX 向上のための入力制御・UI 出し分け | DevTools で突破可能 |
| API | 処理前の権限チェック・入力検証・レート制限 | サーバー側なので突破困難 |
| DB | アクセス権限の最小化 | DB 接続情報がなければ不可 |
| インフラ | IAM・ネットワーク制御・WAF・レート制限・監視・監査 | インフラアクセス権が必要 |

- フロントエンドのチェックは UX 向上が目的。セキュリティの本命は API 層以降
- 1 つの層に依存せず、すべての層で防御する

## プロジェクトのバリデーションツール

- TypeScript: zod / valibot によるスキーマバリデーション
- Python: pydantic によるスキーマバリデーション
- すべてのユーザー入力をサーバーサイドで検証する
- ホワイトリスト方式を優先する
- 常に、入力（関数の引数、クエリ、APIリクエスト）が間違っているという前提で実装する
- ファイルパスを扱う場合は RFI（Remote File Inclusion）・LFI（Local File Inclusion）に注意する。ユーザー入力をファイルパスに直接使わない

## 認証・認可の方針

- パスワード: bcrypt / argon2 でハッシュ化
- トークン: cookie に保存（HttpOnly, Secure, SameSite=Strict）
- JWT: 有効期限を短く設定
- RBAC を実装する
- API 側の権限チェックはミドルウェアで共通化する（エンドポイントごとにロールを指定）
- 権限エラーのレスポンス戦略: 基本は 403 Forbidden、権限不足が予期できる API は空データを返す

## シークレット管理

- ハードコード禁止 → 環境変数 or シークレットマネージャー
- `.env` は `.gitignore` に含める
- ローテーションポリシーを定める

## 依存関係の脆弱性チェック

- `pnpm audit` / `yarn audit` で定期チェック
- Python: `pip-audit` / `safety`
- バージョン固定でサプライチェーン攻撃を最小化（`dependencies` rule 参照）

## セキュリティヘッダー

```
Content-Security-Policy: default-src 'self'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Strict-Transport-Security: max-age=31536000; includeSubDomains
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=()
```

## API セキュリティ

### レート制限

- 認証エンドポイント（ログイン、パスワードリセット等）には厳格なレート制限を設定する
- 一般 API にもグローバルなレート制限を設定する
- インフラ層（WAF）でもレート制限を併用する

### CORS

- 許可オリジンを明示的に指定する（`*` 禁止）
- credentials を含む場合は `Access-Control-Allow-Credentials: true`

## インフラセキュリティ（IaC 破壊的操作の防止）

DataTalks.Club 事故（2026年2月）の教訓。Claude Code が terraform destroy で本番DB + 全スナップショットを削除した実事例に基づく。

### AI エージェントによるインフラ操作の原則

- `terraform plan` まではAIに任せ、`apply` / `destroy` は人間が手動実行する
- `terraform destroy` / `terraform apply -auto-approve` は settings.json + hook で二重ブロック済み
- 承認の形式化に注意: 複雑な操作では承認が形式的になりやすい。成功体験の蓄積で「いつもの延長」感覚が危険

### IAM・最小権限の原則

- サービスアカウント / IAM ロールに必要最小限の権限のみ付与する
- `roles/editor`、`roles/owner`、`AdministratorAccess` 等の広範囲ロールをサービスアカウントに付与しない
- リソースを ARN / リソース名で限定し、`*` を避ける
- 「動くから」で権限を広げたまま放置しない

### ネットワーク分離

- DB はプライベートサブネット / Private IP に配置し、パブリックアクセスを無効化する
- アプリ → DB は VPC Connector / VPC 内接続経由
- ファイアウォール / Security Group で許可する通信を最小限にする
- DB への直接アクセスは踏み台サーバー経由のみ

### 監査ログ

- GCP: Cloud Audit Logs（Admin Activity は自動、Data Access は有効化が必要）
- AWS: CloudTrail（管理イベントは自動、データイベントは有効化が必要）
- セキュリティインシデント時の原因調査・不正操作の検出に使用する

### DB 削除保護（層状防御）

- クラウド側: `deletion_protection = true`（RDS / Cloud SQL）
- Terraform側: `lifecycle { prevent_destroy = true }`
- 自動バックアップはDB削除時に一緒に消える → 手動スナップショットを必ず取得する
- バックアップの復元テストを定期実行する（存在と復元可能性は別）

### Terraform State 管理

- リモートバックエンド（GCS / S3）で管理する（ローカル state 禁止）
- State ロック + 暗号化を有効にする

### 環境分離

- 本番 / 開発 / ステージングはプロジェクト（GCP）またはアカウント（AWS）レベルで分離する
