# Issue #26 実装計画: next を 15.5.22 へ更新し npm audit の high 脆弱性を解消する

- date: 2026-07-30
- issue: https://github.com/kit-kamatsu-yuhi/todo-app/issues/26
- branch: feature/26-next-security-patch

## 1. 要件分析

Week 11 セキュリティ監査の `npm audit` で high 4 件を検出した。対応は依存関係の更新のみで、アプリコードの変更はない。

| 脆弱性 | 経路 | 対応 |
|--------|------|------|
| next 15.5.19 の advisories（Server Actions DoS: GHSA-m99w-x7hq-7vfj、SSRF: GHSA-89xv-2m56-2m9x、cache confusion: GHSA-68g3-v927-f742 ほか） | 直接依存 | 15.5.22 へパッチ更新 |
| postcss / sharp の high | next 同梱の推移的依存 | next 更新で解消（要確認） |
| brace-expansion の DoS | dev 依存の推移的（eslint / glob / test-exclude 経由） | `npm audit fix` |

制約: プロジェクトルールによりバージョンはキャレットなしで固定する。`eslint-config-next` は next と同一バージョンで揃えているため同時に 15.5.22 へ更新する。

### 受入基準の分類

| 受入基準 | 分類 |
|---------|------|
| `npm audit` で high 以上 0 件 | 自動テスト（コマンド検証） |
| テストスイート全通過 | 自動テスト（vitest 既存スイート） |
| ビルド成功（`npm run build`） | 自動テスト（コマンド検証） |
| ログイン〜TODO CRUD の動作 | 手動テスト（デプロイ後の確認。ローカルは既存統合テストで代替） |

## 2-5. UML / API / DB / フロントエンド設計

対象外。依存関係の更新のみで、スキーマ・エンドポイント・UI に変更はない。

## 6. セキュリティ基準

- 本 Issue 自体がセキュリティ対応（既知 CVE / advisory の解消）
- 更新は next 15.5.x 系内のパッチ適用に留め、メジャー/マイナー更新に伴う挙動変更リスクを避ける
- lockfile の差分を確認し、意図しないパッケージの混入がないことを確認する（サプライチェーン対策）

## 7. ロギング要件

対象外。ログ出力の変更はない。

## 8. テスト戦略

新規テストは書かない（依存更新のため）。既存のスイートを回帰確認として使う。

1. `npm run test` — ユニット・統合テスト（SQLite / jsdom）
2. `npm run test:pg` — PostgreSQL 統合テスト（scripts/test-with-postgres.sh）
3. `npm run build` — prisma generate + next build の成功確認
4. `npm run lint` — eslint-config-next 更新後の lint 通過確認
5. `npm audit` — high 以上 0 件の確認

## 9. タスク分解

| # | タスク | 依存 | 見積もり |
|---|--------|------|---------|
| 1 | package.json の next / eslint-config-next を 15.5.22 に更新し `npm install` | - | 0.5h |
| 2 | `npm audit fix` で brace-expansion 等の dev 依存を解消 | 1 | 0.5h |
| 3 | `npm audit` で high 0 件を確認。残件があれば内容を精査して対応方針を記録 | 2 | 0.5h |
| 4 | `npm run test` / `npm run test:pg` / `npm run build` / `npm run lint` の全通過確認 | 3 | 0.5h |
| 5 | raw/ への対応記録 | 4 | 0.5h |

## 10. リスク分析

| リスク | 影響 | 確率 | 対策 |
|--------|------|------|------|
| 15.5.22 で Server Actions の挙動が変わり既存機能が壊れる | 中 | 低 | パッチ更新のみ。既存テスト + build で回帰確認 |
| `npm audit fix` が lockfile を広範囲に書き換える | 低 | 中 | 差分を確認し、対象外の更新が混ざれば個別に絞る |
| audit の advisory 範囲表記（〜16.3.0-preview.7）により 15.5.22 でも警告が残る | 低 | 低 | 残った場合は advisory 本文で 15.5.22 の修正状況を確認し、結果を記録 |

## 実行フロー

1. ✅ `/plan-issue` — 計画策定（完了）
2. ⬜ ユーザー承認 — plan.md + todos.md の内容を確認してもらう
3. ⬜ `/codex-team all` — 実装/テスト/レビュー（codex sub-agent チームで実行）
   - codex-implement + codex-test: 実装・テスト（Agent ツールで並列起動）
   - codex-review + review-agent: レビュー（Agent ツールで並列起動）
   - acceptance-criteria-agent: 受入基準 RED/GREEN 判定
4. ⬜ `/create-pr` — PR 作成（/walkthrough → changes.md → PR）
