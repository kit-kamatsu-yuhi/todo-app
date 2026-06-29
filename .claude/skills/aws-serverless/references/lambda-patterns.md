# Lambda 設計パターン

## イベントソース別パターン

### API Gateway 統合

```
API Gateway → Lambda → DynamoDB / RDS
```

同期呼び出し。レスポンスを直接返す。タイムアウトは API Gateway 側で最大30秒。

### SQS トリガー

```
Producer → SQS → Lambda → 処理
```

非同期処理。バッチサイズ・バッチウィンドウで効率化する。DLQ（Dead Letter Queue）でエラーを捕捉する。

### EventBridge ルール

```
EventBridge → Lambda
```

スケジュール実行（cron）やサービス間イベント連携に使う。

### S3 イベント

```
S3 (PutObject) → Lambda → 画像リサイズ / データ変換
```

ファイルアップロードをトリガーにバックグラウンド処理を実行する。

## エラーハンドリング

### 同期呼び出し（API Gateway）

- Lambda 内で try-catch し、適切な HTTP ステータスコードを返す
- 未処理例外は 500 になる

### 非同期呼び出し（SQS / EventBridge）

- 最大リトライ回数を設定する（デフォルト: 2回）
- リトライ超過時は DLQ または Lambda Destination に送る
- べき等性を担保する（DynamoDB の条件付き書き込み等）

## コールドスタート対策

| 対策 | 効果 | コスト影響 |
|------|------|-----------|
| Provisioned Concurrency | コールドスタートなし | 常時課金 |
| SnapStart (Java) | 起動時間を短縮 | 追加コストなし |
| メモリ増加 | 初期化が速くなる | メモリ単価 × 時間 |
| 依存関係の最小化 | パッケージサイズ削減 | なし |
| Lambda Layer | 共通ライブラリの分離 | なし |
