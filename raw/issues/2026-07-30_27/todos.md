# タスクリスト（Issue #27）

## 実装タスク

- [x] タスク1: `next.config.ts` に `headers()` を実装し 6 ヘッダーを全ルートに付与（CSP は NODE_ENV で `'unsafe-eval'` を分岐）（見積もり: 1h）
  - レビュー指摘により分岐は `=== 'development'` の fail-closed に変更（result.md 参照）
  - 追加対応: `.eslintrc.json` に `react/no-danger: error`（'unsafe-inline' 前提条件の機械検知）

## テストタスク

- [x] テスト1: `tests/security-headers.test.ts` を追加（4 テスト GREEN。headers() の出力検証・本番 CSP に unsafe-eval が混入しないこと）
- [x] テスト2: `npm run build && npm start` + curl でヘッダー実在確認（200 / 503 / 307 の 3 応答クラスで確認済み）。ブラウザでの CSP violation ゼロ確認は手動テストとして残（result.md のチェックリスト）
- [x] テスト3: フルスイート（scripts/test-with-postgres.sh で 104 テスト）/ `npm run lint` の回帰確認

## ドキュメントタスク

- [x] `raw/` コンテキスト記録（採用 CSP 値・nonce 方式見送りの判断・dangerouslySetInnerHTML 導入時の再検討条件）→ result.md
