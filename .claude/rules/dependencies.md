---
paths: "**/package.json, **/pyproject.toml, **/go.mod, **/build.gradle.kts, **/Cargo.toml, **/Package.swift, **/pom.xml, **/libs.versions.toml"
---

# 依存関係管理

言語固有のルールは `languages/` 配下の各言語ファイルを参照。

## 共通ルール

- 新しい依存関係を追加する前に、既存の依存で代替できないか検討する
- 依存関係の追加時はライセンスを確認する（MIT, Apache-2.0 等の許容ライセンス）
- セキュリティ脆弱性のある依存は速やかに更新する
- Dependabot / Renovate を有効化し、依存関係の自動更新を行う
- 未使用の依存関係は定期的に削除する
