---
name: estimate
description: Issue完了見積もり。週あたりのIssue消化数と残Issueから、完了までの週数を見積もる。GitHub Projectsとの連携も可能。
argument-hint: "[GitHub ProjectsのURL（省略可）]"
---

# Issue 完了見積もり

プロジェクトの Issue 消化ペースを基に、完了までの週数を見積もる。

## 参照スキル

- `estimation-methods` — 見積もり手法（ストーリーポイント・三点見積もり・類推見積もり）・バッファ管理・MoSCoW法

## 手順

1. **ベロシティの取得**
   - GitHub Projects の URL が提供された場合:
     - `gh api` で Projects のデータを取得する
     - 過去の完了 Issue 数から週あたりの消化数を算出する
   - URL が提供されない場合:
     - ユーザーに週あたりの Issue 消化数を質問する

2. **残 Issue の取得**
   - GitHub Projects の URL が提供された場合:
     - Projects から未完了 Issue 数を取得する
   - URL が提供されない場合:
     - `gh issue list --state open` で未解決 Issue 数を取得する
     - またはユーザーに残 Issue 数を質問する

3. **見積もり計算**
   - 残 Issue 数 / 週あたりの Issue 消化数 = 完了までの週数
   - `estimation-methods` skill の三点見積もり（PERT）を適用する:
     - 楽観値 = 残 Issue 数 / ベロシティ上限
     - 最頻値 = 残 Issue 数 / 平均ベロシティ
     - 悲観値 = 残 Issue 数 / ベロシティ下限（または最頻値 × 1.5）
     - 期待値 = (O + 4M + P) / 6
   - MoSCoW法で Issue を分類し、Must のみ / Must+Should の段階的見積もりも提示する

4. **出力**
   - 週あたりの Issue 消化数（ベロシティ）
   - 残 Issue 数
   - 完了見積もり: 約 N 週間（楽観: N 週 / 悲観: N 週）
