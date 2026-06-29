# コミットメッセージ規約

## Conventional Commits 準拠

```
<type>(<scope>): <subject>

<body>

<footer>
```

## Type 一覧

| Type | 用途 |
|------|------|
| `feat` | 新機能の追加 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみの変更 |
| `style` | コードの意味に影響しない変更（空白、フォーマット等） |
| `refactor` | バグ修正も機能追加もしないコード変更 |
| `perf` | パフォーマンス改善 |
| `test` | テストの追加・修正 |
| `chore` | ビルドプロセスや補助ツールの変更 |
| `ci` | CI 設定の変更 |

## ルール

- subject は命令形で記述する（日本語の場合は「〜する」の体言止め）
- subject の末尾にピリオドを付けない
- subject は 50 文字以内を目安とする
- body は「なぜ」この変更が必要かを説明する
- Issue 番号は footer に記載する: `Refs: #42` / `Closes: #42`

## 例

```
feat(auth): ユーザー認証機能の追加

OAuth 2.0 を使用した Google ログインを実装。
セッション管理には JWT を採用。

Closes: #42
```

## Breaking Changes

破壊的変更がある場合:
- type の後に `!` を付ける: `feat!: API レスポンス形式の変更`
- footer に `BREAKING CHANGE:` を記載する
