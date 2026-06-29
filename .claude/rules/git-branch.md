# Git ブランチ戦略（GitHub Flow）

## ブランチ構成

- **main**: 本番リリース可能な状態を常に維持
- **feature/\***: 機能開発・バグ修正用の短命ブランチ

## ワークフロー

1. `main` から feature ブランチを作成する
2. feature ブランチで開発・コミットする
3. PR を作成し、レビューを受ける
4. staging 環境にデプロイし、人間が動作確認する
5. 動作確認を通ったら、production 環境にデプロイする
6. `main` にマージする
7. マージ後、feature ブランチを削除する

## ブランチ命名規則

```
feature/<issue番号>-<簡潔な説明>
```

例:
- `feature/42-add-user-auth`
- `feature/15-fix-login-redirect`

## 保護ブランチ

- `main` は直接 push 禁止
- PR 経由でのみマージ可能
- CI 通過とレビュー承認を必須とする

## マージ戦略

- Squash merge を基本とする（コミット履歴をクリーンに保つ）
- マージコミットメッセージは Conventional Commits に準拠する
