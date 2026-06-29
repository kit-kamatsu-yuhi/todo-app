---
paths: "**/*.ts, **/*.tsx, **/*.py, **/*.go, **/*.kt, **/*.kts, **/*.rs, **/*.java, **/*.swift"
---

# 命名規則

言語固有のルールは `languages/` 配下の各言語ファイルを参照。

## 共通ルール

- 略語は避け、意味が明確な名前を付ける
- ブール値は `is`, `has`, `can`, `should` プレフィックスを使う
- コレクションは複数形を使う: `users`, `items`
- コールバック/ハンドラは `on` プレフィックス: `onSubmit`, `on_click`
- ディレクトリ名は kebab-case: `user-management/`
