# Issue #27 対応記録: セキュリティヘッダーの全ルート付与

- date: 2026-07-30
- branch: feature/27-security-headers

## 実施内容

- `next.config.ts` に `headers()` を実装し、`source: '/(.*)'` で全ルートに 6 ヘッダーを付与
- `tests/security-headers.test.ts` を新規追加（4 テスト。ヘッダー期待値の完全一致 + NODE_ENV 両分岐）
- `.eslintrc.json` に `react/no-danger: error` を追加（後述の CSP 前提条件を lint で機械検知するため）

## 採用した CSP

```
default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'
```

開発モード（`NODE_ENV === 'development'`）のみ script-src に `'unsafe-eval'` を追加する（next dev の HMR 対応）。

### plan からの変更点

plan.md §1 は分岐条件を `NODE_ENV !== 'production'` と規定していたが、レビュー指摘（codex-review / review-agent の両方）により `=== 'development'` の fail-closed に変更した。test や未設定の環境で `'unsafe-eval'` が混入しない。`next build` / `next start` は production、`next dev` は development を強制するため、実運用の挙動は変わらない。

## nonce 方式を見送った判断

- Next.js の仕様で nonce を使うと全ページが動的レンダリングに強制され、/login /signup の静的生成が失われる
- 本アプリは DOM 直接挿入ゼロ（`innerHTML` / `dangerouslySetInnerHTML` / `document.write` / `insertAdjacentHTML` の grep ヒットなし。レビューで独立再確認済み）、外部 CDN・外部フォント・next/font・next/image も未使用
- この前提が崩れたら nonce 方式へ移行を再検討する。トリガーは次の 2 つ
  1. `dangerouslySetInnerHTML` の導入（`react/no-danger` の lint エラーで機械検知される）
  2. 外部スクリプト・外部リソースの導入（CSP の許可リスト変更が必要になった時点）

## 検証結果

| 確認 | 結果 |
|------|------|
| `tests/security-headers.test.ts` | 4/4 GREEN |
| フルスイート `scripts/test-with-postgres.sh` | 15 ファイル 104 テスト全通過 |
| `npm run build` | 成功。routes-manifest.json に本番 CSP（unsafe-eval なし）が焼き込まれることを確認 |
| `npm run lint` | エラーなし |
| 実応答（next start + curl） | /login（200 静的）・/api/health（503 API Route）・/（307 middleware リダイレクト）の 3 応答クラスすべてで 6 ヘッダー付与を確認 |

## 残る手動テスト（マージ前〜staging 確認時）

- [ ] ブラウザでログイン → TODO の作成・編集・削除・並び替え・カテゴリ操作を実行し、DevTools console に CSP violation が出ないことを確認
- [ ] `npm run dev` で HMR が動作することを確認（`'unsafe-eval'` 分岐と `connect-src 'self'` の ws 許容）
- [ ] デプロイ後、staging（gcloud run services proxy 経由）で同じ確認

## 運用メモ

- CSP の `'unsafe-inline'` 許容は「DOM 直接挿入ゼロ」が前提。next.config.ts のコメントと `react/no-danger` lint がこの前提を守る仕掛け
- 外部リソースを導入するときは CSP の該当ディレクティブ（script-src / img-src / font-src / connect-src）への許可リスト追加が必要
