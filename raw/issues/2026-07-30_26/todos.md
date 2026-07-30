# タスクリスト（Issue #26）

## 実装タスク

- [x] タスク1: package.json の next / eslint-config-next を 15.5.22 に更新し `npm install`（見積もり: 0.5h）
- [x] タスク2: `npm audit fix` で dev 依存（brace-expansion 等）の脆弱性を解消（見積もり: 0.5h）
- [x] タスク3: `npm audit --omit=dev` で production の high 0 件を確認。フル audit の残件は精査して方針を記録（見積もり: 0.5h）
  - production（--omit=dev）は全 severity 0 件。フルでは GHSA-mh99-v99m-4gvg（dev 専用・解消には eslint 10 破壊的更新が必要）のみ残存 → result.md に記録
  - 追加対応: overrides で postcss 8.5.25 / sharp 0.35.3 を強制し production の high を解消

## テストタスク

- [x] テスト1: `npm run test`（ユニット・統合）全通過（100/100）
- [x] テスト2: `npm run test:pg`（PostgreSQL 統合）全通過（100/100）
- [x] テスト3: `npm run build` 成功
- [x] テスト4: `npm run lint` 通過

## ドキュメントタスク

- [x] `raw/` コンテキスト記録（対応内容・audit 結果）→ result.md
