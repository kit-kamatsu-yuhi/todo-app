# Issue #27: セキュリティヘッダー（CSP / HSTS / X-Content-Type-Options 等）を全ルートに付与する

- date: 2026-07-30
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/27
- labels: feat, priority:high, size:M
- 出典: Week 11 セキュリティ監査（raw/conversations/2026-07-30_week11-security-audit.md）

## 背景

`next.config.ts` に `headers()` がなく、CSP / X-Content-Type-Options / HSTS / X-Frame-Options / Referrer-Policy / Permissions-Policy が全ルート未設定。

## 設計メモ

- security skill のヘッダーセットをベースにする。CSP は `default-src 'self'` 起点で、Next.js のハイドレーション用 inline script に合わせて script-src / style-src を調整する必要がある
- 適用後にログイン〜TODO CRUD（Server Actions）が CSP 違反なく動くことが受入条件
- 厳格化で壊れる場合は Report-Only で違反レポートを確認してから enforce に切り替える手順を検討する
