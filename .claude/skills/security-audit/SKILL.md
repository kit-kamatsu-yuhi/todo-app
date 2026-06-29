---
name: security-audit
description: セキュリティ監査を実行する。security skillの観点に基づき、コードの脆弱性を検出・報告する。
argument-hint: "[対象ファイルやディレクトリ（省略可）]"
---

# セキュリティ監査

$ARGUMENTS に対してセキュリティ監査を実施する。

## 手順

1. **コードのセキュリティレビュー**
   - `security` skill の観点に従ってコードをチェックする

2. **依存関係の脆弱性スキャン**
   - `pnpm audit` / `yarn audit` を実行する
   - Python: `pip-audit` を実行する
   - 既知の CVE がある依存を特定する

3. **シークレット検出**
   - APIキー、パスワード、トークンがコードにハードコードされていないか確認する
   - `.env` ファイルが `.gitignore` に含まれているか確認する

4. **レポート出力**
   - 発見した脆弱性を重要度（Critical/High/Medium/Low）で分類する
   - 各脆弱性に対する修正案を提示する
   - `wiki/pages/security/` に知見を記録する
