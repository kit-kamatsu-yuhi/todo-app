---
name: monitoring
description: モニタリング/可観測性スキル。ロギング・分散トレーシング・メトリクス・アラート設計の依頼時に使用する。プロジェクト固有の可観測性方針を提供する。
---

# モニタリング / 可観測性 Skill

プロジェクト固有の可観測性方針。可観測性の一般概念は省略する。

## 三本柱

| 柱 | 目的 | 用途 |
|----|------|------|
| ログ | 個別イベントの記録 | デバッグ、監査、障害調査 |
| メトリクス | 集計された計測値 | ダッシュボード、アラート、傾向分析 |
| トレース | リクエストの経路追跡 | レイテンシ分析、ボトルネック特定 |

## ロギング方針

### 構造化ログ

- JSON 形式で出力する
- 必須フィールド: `timestamp`, `level`, `message`, `service`, `request_id`
- ユーザー識別情報（メールアドレス、氏名等）はマスキングする

### ログレベル

| レベル | 用途 |
|--------|------|
| ERROR | 即座に対処が必要な異常（外部サービス障害、データ不整合等） |
| WARN | 対処は不要だが注視すべき事象（リトライ発生、閾値接近等） |
| INFO | 正常な業務イベント（リクエスト処理完了、バッチ実行等） |
| DEBUG | 開発時のみ有用な詳細情報（変数値、SQL クエリ等） |

### TypeScript

```typescript
// pino を推奨
import pino from "pino";

const logger = pino({
  level: process.env.LOG_LEVEL || "info",
  formatters: {
    level: (label) => ({ level: label }),
  },
});

// リクエストごとに child logger を生成
const reqLogger = logger.child({ requestId, userId });
reqLogger.info({ action: "order_created", orderId }, "注文を作成しました");
```

### Python

```python
# structlog を推奨
import structlog

logger = structlog.get_logger()

# コンテキスト付きログ
logger.info("order_created", order_id=order_id, user_id=user_id)
```

### 禁止事項

- パスワード、トークン、クレジットカード番号をログに含めない
- DEBUG レベルを本番環境で有効にしない
- 大量のログを同期的に出力してパフォーマンスを劣化させない

## メトリクス方針

### 計測すべき指標

| カテゴリ | 指標 | 型 |
|---------|------|-----|
| RED | Request rate（リクエスト数/秒） | Counter |
| RED | Error rate（エラー率） | Counter |
| RED | Duration（レスポンス時間） | Histogram |
| USE | Utilization（CPU / メモリ使用率） | Gauge |
| USE | Saturation（キュー長、接続プール使用率） | Gauge |
| USE | Errors（システムエラー数） | Counter |
| ビジネス | 登録数、注文数、売上等 | Counter / Gauge |

### ラベル設計

- カーディナリティが高すぎるラベル（ユーザーID、リクエストID等）は使わない
- 推奨ラベル: `service`, `endpoint`, `method`, `status_code`, `environment`

## 分散トレーシング方針

### OpenTelemetry

- OpenTelemetry SDK を使用して計装する
- HTTP ヘッダーで `traceparent` を伝播する（W3C Trace Context）
- 自動計装（HTTP クライアント、DB クライアント）を優先し、手動計装は重要な業務処理に限定する

### スパンの設計

- スパン名はオペレーション名にする（`GET /api/users`, `db.query` 等）
- エラー時はスパンにエラー情報を付与する
- 重要な属性（クエリパラメータ、レスポンスサイズ等）をスパンに記録する

## アラート設計

### アラートルール

| 重要度 | 条件例 | 通知先 |
|--------|-------|--------|
| Critical | エラー率 > 5%（5分間） | Slack + PagerDuty |
| Critical | レスポンス時間 p99 > 5秒（5分間） | Slack + PagerDuty |
| Warning | エラー率 > 1%（10分間） | Slack |
| Warning | CPU 使用率 > 80%（10分間） | Slack |
| Info | デプロイ完了 | Slack |

### アラート設計原則

- アクショナブルなアラートのみ設定する（対処方法が不明なアラートは作らない）
- フラッピング防止のため、十分な評価期間を設ける
- アラート疲れを防ぐため、定期的にアラートルールを見直す

## ダッシュボード構成

### 推奨ダッシュボード

1. **サービス概要** — RED メトリクス、エラー率、レスポンス時間分布
2. **インフラ** — CPU / メモリ / ディスク / ネットワーク
3. **ビジネス** — KPI メトリクス（登録数、注文数等）
4. **データベース** — クエリ実行時間、接続プール、スロークエリ

## ドキュメント出力先

- 監視設計 → `wiki/pages/infrastructure/` に記録
- インシデント対応記録 → `raw/conversations/` に記録
