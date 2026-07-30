# Issue #27 実装計画: セキュリティヘッダーを全ルートに付与する

- date: 2026-07-30
- issue: https://github.com/kit-kamatsu-yuhi/todo-app/issues/27
- branch: feature/27-security-headers

## 1. 要件分析

Week 11 監査で `next.config.ts` に `headers()` がなく、セキュリティヘッダーが全ルート未設定と判明した。security skill 指定の 6 ヘッダーを付与する。

### 設計判断: CSP は静的付与を採用（nonce 方式は見送り）

| 方式 | 内容 | 判断 |
|------|------|------|
| 静的 CSP（採用） | `next.config.ts` の `headers()` で固定値を付与。script-src / style-src に `'unsafe-inline'` を許容 | 差分が next.config.ts に閉じる。レンダリング挙動が変わらない |
| nonce + strict-dynamic | middleware で nonce 生成 | Next.js の仕様で全ページが動的レンダリングに強制され、/login /signup の静的生成が失われる。本アプリは React の自動エスケープのみで DOM 挿入がなく（監査で innerHTML ゼロ確認済み）、nonce 化の便益が影響に見合わない。強化する場合は別 Issue |

### 付与するヘッダー

| ヘッダー | 値 |
|---------|-----|
| Content-Security-Policy | `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'` |
| X-Content-Type-Options | `nosniff` |
| Strict-Transport-Security | `max-age=31536000; includeSubDomains` |
| X-Frame-Options | `DENY`（frame-ancestors と二重防御。旧ブラウザ向け） |
| Referrer-Policy | `strict-origin-when-cross-origin` |
| Permissions-Policy | `camera=(), microphone=()` |

- 開発モード（next dev）は HMR が `'unsafe-eval'` を要求するため、`NODE_ENV !== 'production'` のときのみ script-src に `'unsafe-eval'` を追加する
- HSTS は Cloud Run が TLS 終端する本番で意味を持つ。ローカル HTTP でも付与して害はない（ブラウザは HTTPS 応答でのみ記憶する）

### 受入基準の分類

| 受入基準 | 分類 |
|---------|------|
| 全ルートの応答に 6 ヘッダーが含まれる | 自動テスト（next.config の headers() 出力検証）+ 手動テスト（build + start 後に curl で実応答確認） |
| ログイン〜TODO CRUD が CSP 違反なく動作 | 手動テスト（ブラウザ console で CSP violation がないこと）。ロジック回帰は既存スイートで担保 |

## 2-4. UML / API / DB 設計

対象外。HTTP 応答ヘッダーの追加のみで、エンティティ・エンドポイント・スキーマに変更はない。

## 5. フロントエンド設計

UI 変更なし。CSP の影響を受けるのは Next.js が生成する inline script（ハイドレーション）と inline style で、`'unsafe-inline'` 許容により既存挙動を維持する。外部 CDN・外部フォント・外部画像は未使用のため許可リストへの追加はない。

## 6. セキュリティ基準

- CSP の `frame-ancestors 'none'` + `X-Frame-Options: DENY` でクリックジャッキングを遮断する
- `object-src 'none'` / `base-uri 'self'` / `form-action 'self'` でインジェクション時の影響を限定する
- script-src の `'unsafe-inline'` は Next.js の inline script 都合による許容。DOM 直接挿入ゼロ（監査確認済み）が前提であり、`dangerouslySetInnerHTML` を導入する場合は nonce 方式への移行を再検討する（result.md に運用メモとして残す）

## 7. ロギング要件

対象外。ヘッダー付与にログは伴わない。CSP violation report の収集（report-to）は本 Issue のスコープ外とする。

## 8. テスト戦略

1. **自動テスト（新規）**: `tests/security-headers.test.ts` — `next.config.ts` の `headers()` を呼び出し、(a) 全ルート対象の source パターンであること、(b) 6 ヘッダーが期待値で含まれること、(c) 本番モードの script-src に `'unsafe-eval'` が含まれないことを検証する
2. **既存スイート回帰**: `npm run test` / `npm run test:pg`（100 テスト）
3. **ビルド検証**: `npm run build` + `npm run lint`
4. **手動テスト**: `npm run build && npm start` に対して curl でヘッダー実在を確認。ブラウザでログイン〜TODO CRUD を操作し console に CSP violation が出ないことを確認（デプロイ後は staging でも同様）

## 9. タスク分解

| # | タスク | 依存 | 見積もり |
|---|--------|------|---------|
| 1 | `next.config.ts` に `headers()` を実装（CSP は NODE_ENV で分岐） | - | 1h |
| 2 | `tests/security-headers.test.ts` を追加 | 1 | 1h |
| 3 | build + start + curl でヘッダー実在と CSP violation 有無を確認 | 1 | 0.5h |
| 4 | 既存スイート・lint の回帰確認 | 1-2 | 0.5h |
| 5 | raw/ への対応記録（採用した CSP 値と nonce 見送りの判断） | 3-4 | 0.5h |

## 10. リスク分析

| リスク | 影響 | 確率 | 対策 |
|--------|------|------|------|
| CSP が Next.js の inline script / style をブロックし画面が壊れる | 高 | 中 | `'unsafe-inline'` を許容する値から開始し、手動テスト（タスク3）で violation ゼロを確認してから確定する |
| next dev で HMR が CSP に阻まれ開発体験が壊れる | 中 | 中 | 開発モードのみ `'unsafe-eval'` を追加。タスク3 で dev / prod 両方を確認 |
| 認証プロキシ（gcloud run services proxy）経由の到達確認で CSP が想定外に作用する | 低 | 低 | connect-src / form-action は 'self' 基準で、プロキシは同一オリジンに見えるため影響なしの見込み。デプロイ後の手動確認に含める |

## 実行フロー

1. ✅ `/plan-issue` — 計画策定（完了）
2. ⬜ ユーザー承認 — plan.md + todos.md の内容を確認してもらう
3. ⬜ `/codex-team all` — 実装/テスト/レビュー（codex sub-agent チームで実行）
   - codex-implement + codex-test: 実装・テスト（Agent ツールで並列起動）
   - codex-review + review-agent: レビュー（Agent ツールで並列起動）
   - acceptance-criteria-agent: 受入基準 RED/GREEN 判定
4. ⬜ `/create-pr` — PR 作成（/walkthrough → changes.md → PR）
