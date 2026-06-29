# AWS データベース選定リファレンス

## アクセスパターン別推奨

### CRUD API（TODO アプリ等）

**推奨: RDS PostgreSQL**

- 正規化されたテーブル設計
- JOIN による関連データ取得
- トランザクション保証
- 月額 $15〜（db.t3.micro）

### 高トラフィック API（SNS、EC 等）

**推奨: Aurora PostgreSQL + ElastiCache**

- Aurora のリードレプリカで読み取り分散
- ElastiCache で頻繁なクエリ結果をキャッシュ
- 自動フェイルオーバーで高可用性

### IoT / リアルタイムデータ

**推奨: DynamoDB**

- 書き込みスループットが無限にスケール
- TTL でデータの自動削除
- DynamoDB Streams でイベント駆動処理

### セッション管理

**推奨: ElastiCache (Redis) または DynamoDB**

- Redis: 低レイテンシ、TTL、データ構造が豊富
- DynamoDB: サーバーレス、運用不要、TTL 対応

## DynamoDB テーブル設計

### シングルテーブル設計

```
PK          | SK              | データ
USER#123    | PROFILE         | { name, email, ... }
USER#123    | TODO#001        | { title, completed, ... }
USER#123    | TODO#002        | { title, completed, ... }
```

- PK（パーティションキー）+ SK（ソートキー）で柔軟なアクセスパターン
- GSI（グローバルセカンダリインデックス）で逆引きクエリ
- 正規化しない。読み取りパターンに最適化する

## マイグレーション戦略

### RDS → Aurora

- Aurora リードレプリカを RDS に追加し、昇格する方法が最もダウンタイムが短い
- pg_dump / pg_restore はデータ量に比例してダウンタイムが長くなる

### オンプレミス → AWS

- AWS DMS（Database Migration Service）を使う
- 同種 DB 間は簡単。異種 DB 間は SCT（Schema Conversion Tool）で変換する
