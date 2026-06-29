---
name: ci-cd
description: CI/CDパイプラインスキル。GitHub Actions ワークフロー、デプロイ戦略、環境管理の依頼時に使用する。プロジェクト固有のCI/CD方針を提供する。
---

# CI/CD パイプライン Skill

プロジェクト固有の CI/CD 方針。GitHub Actions の一般的な構文は省略する。

## パイプライン構成

### CI（継続的インテグレーション）

PR 作成時・更新時に自動実行する:

1. **リント・フォーマット** — Biome (TypeScript), ruff (Python)
2. **型チェック** — TypeScript strict, mypy strict
3. **テスト実行** — Unit + Integration、カバレッジレポート生成
4. **セキュリティスキャン** — 依存関係の脆弱性チェック
5. **ビルド** — 成果物の生成

### CD（継続的デリバリー）

- main マージ後に staging へ自動デプロイ
- staging での動作確認後、手動承認で production デプロイ

## GitHub Actions ワークフロー構成

```
.github/workflows/
├── ci.yml           # PR 時の CI パイプライン
├── deploy-staging.yml   # staging デプロイ
└── deploy-production.yml # production デプロイ（手動承認）
```

## CI ワークフローの必須ジョブ

| ジョブ | 内容 | 失敗時 |
|-------|------|--------|
| lint | Biome check / ruff check | PR ブロック |
| typecheck | tsc --noEmit / mypy | PR ブロック |
| test | テスト実行 + カバレッジ | PR ブロック（80%未満） |
| security | pnpm audit / pip-audit | PR ブロック（critical/high） |
| build | ビルド成功確認 | PR ブロック |

## デプロイ戦略

- **staging**: main マージ後に自動デプロイ
- **production**: staging 動作確認後、手動承認でデプロイ
- ロールバック手順を常に準備する
- データベースマイグレーションはデプロイ前に実行する

## 環境変数管理

- GitHub Secrets / Environment secrets を使用する
- 環境ごとに分離する（staging / production）
- `.env.example` をリポジトリに含める（実際の値は含めない）

## キャッシュ戦略

- `node_modules` / `.pnpm-store` をキャッシュする
- Python の仮想環境・pip キャッシュを保持する
- Docker レイヤーキャッシュを活用する

## ブランチ保護ルール

- main への直接 push を禁止する
- CI 全ジョブの通過を必須とする
- レビュー承認 1 名以上を必須とする
- `git-branch` rule と整合させる
