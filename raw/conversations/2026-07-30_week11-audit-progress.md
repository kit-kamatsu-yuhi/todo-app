# Week 11 セキュリティ監査: 対策の進捗（セッション 2026-07-30 終了時点）

- date: 2026-07-30
- topic: 監査後の対策 Issue 起票と #26 / #27 の実装完了、#28 の計画承認待ち

## 実施内容

- 監査記録の PR #29 を作成（本ブランチ。ドキュメントのみ）
- 対策 Issue を 3 件起票: #26（next パッチ更新）、#27（セキュリティヘッダー）、#28（DB 権限分離）
- Issue #26 完了 → PR #30。next / eslint-config-next 15.5.22 化 + overrides（postcss 8.5.25 / sharp 0.35.3）で production 依存ツリーの脆弱性 0 件。テスト 100/100 × 2 系統
- Issue #27 完了 → PR #31。next.config.ts の headers() で 6 ヘッダー付与、react/no-danger lint 追加、新規テスト 4/4 GREEN、フルスイート 104 テスト通過
- Issue #28 は Phase A 完了（plan.md / todos.md を feature/28-db-role-separation に作成済み）。ユーザー承認待ち

## 決定事項

- npm audit の dev 専用残存 advisory（GHSA-mh99-v99m-4gvg、brace-expansion）は本番非搭載のため許容候補。最終承認は PR #30 のマージ判断に委ねる。解消には eslint 10 破壊的更新が必要で、フォローアップ Issue の起票は未実施
- CSP は 'unsafe-inline' 許容の静的付与を採用（nonce 方式は静的生成の喪失により見送り。判断は raw/issues/2026-07-30_27/result.md）
- #28 は「Cloud Run Job で migrate 実行 + todo_migrate / todo_app の権限分離 + CD 順序変更」の設計。terraform apply・SQL 投入・タグ push は人間実行

## 現在のプロジェクト状態

| 項目 | 状態 |
|------|------|
| PR #29（監査記録） | レビュー・マージ待ち |
| PR #30（#26 依存更新） | レビュー・マージ待ち。マージ条件 2 点（残存 advisory 許容、eslint 10 Issue 起票）を本文に記載 |
| PR #31（#27 ヘッダー） | レビュー・マージ待ち。手動テスト（ブラウザ CSP violation 確認）が残 |
| Issue #28 | Phase A 完了・計画承認待ち。worktree: .claude/worktrees/28-db-role-separation |
| Week 12 発表 | 監査結果と対策 3 Issue の進捗が骨子。スライド化は未着手（必要なら kit-pptx） |

## 未解決事項

- #28 の計画承認 → 承認後に /codex-team all（Terraform + SQL + パイプライン実装）
- eslint 10 移行のフォローアップ Issue 起票（PR #30 のマージ条件 2）
- PR #31 マージ前後の手動テスト消化（ブラウザ / dev HMR / staging）
- Medium 以下の監査残項目（セッション ID の CSPRNG 化、レート制限、password max(72)、tfstate リモート化）は未起票のまま
