# Issue #26: next を 15.5.22 へ更新し npm audit の high 脆弱性を解消する

- date: 2026-07-30
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/26
- labels: bug, priority:high, size:S
- 出典: Week 11 セキュリティ監査（raw/conversations/2026-07-30_week11-security-audit.md）

## 背景

`npm audit` で high 4 件。next 15.5.19 に対する advisories（Server Actions DoS: GHSA-m99w-x7hq-7vfj、SSRF: GHSA-89xv-2m56-2m9x、cache confusion: GHSA-68g3-v927-f742 ほか）。postcss / sharp の high は next 同梱の推移的依存。brace-expansion は dev 依存の推移的（DoS）。

## 設計メモ

- バージョン固定運用（キャレット禁止）を維持したまま 15.5.19 → 15.5.22 のパッチ更新
- postcss / sharp は next 更新で解消見込み。brace-expansion は `npm audit fix`
- 受入検証は `npm audit` の high 0 件 + テスト全通過
