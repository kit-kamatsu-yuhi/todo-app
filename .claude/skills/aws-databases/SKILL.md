---
name: aws-databases
description: AWS データベース選定ガイド（RDS・Aurora・DynamoDB・ElastiCache の比較と設計指針）
user_invocable: false
---

# AWS Databases

awslabs/agent-plugins の databases-on-aws 知識に基づく DB 選定スキル。

## DB 選定フローチャート

```
データモデルは? → リレーショナル → 規模は?
                                    → 小〜中規模 → RDS PostgreSQL
                                    → 大規模・高可用性 → Aurora PostgreSQL
                                    → 可変ワークロード → Aurora Serverless v2
               → キーバリュー/ドキュメント → DynamoDB
               → グラフ → Neptune
               → 時系列 → Timestream

キャッシュが必要? → Yes → ElastiCache (Redis)
```

## サービス比較

| サービス | データモデル | スケーリング | 料金モデル | 運用負荷 |
|---------|-----------|------------|-----------|---------|
| RDS PostgreSQL | リレーショナル | 垂直（インスタンスサイズ変更） | インスタンス時間 | 低 |
| Aurora PostgreSQL | リレーショナル | 垂直 + リードレプリカ（最大15台） | インスタンス時間 | 低 |
| Aurora Serverless v2 | リレーショナル | 自動（ACU 0.5〜128） | ACU × 時間 | 最小 |
| Aurora DSQL | リレーショナル | 分散 SQL（マルチリージョン） | リクエスト + ストレージ | 最小 |
| DynamoDB | キーバリュー/ドキュメント | 水平（自動） | キャパシティ + ストレージ | 最小 |
| ElastiCache (Redis) | キーバリュー | 垂直 + シャーディング | ノード時間 | 中 |

## 選定ガイドライン

### RDS PostgreSQL を選ぶとき

- リレーショナルデータ（正規化された OLTP）
- 小〜中規模（〜数百万行）
- 複雑なクエリ（JOIN、集計）が必要
- コストを抑えたい

### Aurora PostgreSQL を選ぶとき

- RDS では性能が足りない
- リードレプリカで読み取りを分散したい
- 自動フェイルオーバーが必要
- ストレージが自動拡張してほしい

### DynamoDB を選ぶとき

- キーバリューアクセスパターン
- シングルミリ秒のレイテンシが必要
- 無限にスケールしたい
- スキーマレスなデータ

### ElastiCache を選ぶとき

- DB クエリ結果のキャッシュ
- セッション管理
- リアルタイムランキング

## 関連スキル

| 名前 | 関係 |
|------|------|
| aws-deploy | DB 選定結果をデプロイ構成に反映 |
| db-design | 論理設計（正規化・ER 図）は db-design スキルを参照 |
