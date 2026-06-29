# ID 戦略リファレンス

## ID 技術比較

| 技術 | 時間ソート | 分散生成 | 推測耐性 | DB 互換性 | 推奨度 |
|------|-----------|---------|---------|-----------|--------|
| AUTO_INCREMENT / IDENTITY | ○ | ✕（単一DB依存） | ✕（連番で推測可能） | 全RDBMS | △ 閉じた内部システム向け |
| UUIDv4 | ✕（ランダム） | ○ | ○ | 全RDBMS | ✕ 新規非推奨（既存は現状維持可） |
| Snowflake ID | ○ | ○（ワーカーID必要） | △（時刻部分は推測可能） | BIGINT として格納 | △ 大規模分散向け |
| ULID | ○ | ○ | △（ミリ秒精度で推測可能） | VARCHAR / BINARY | △ DB ネイティブサポートなし |
| CUID2 | ✕（セキュリティ優先） | ○ | ○ | VARCHAR | △ 特殊用途向け |
| **UUIDv7** | **○** | **○** | **△（時刻部分は推測可能）** | **全RDBMS（UUID型）** | **◎ 新規プロジェクトの標準** |

## B-Tree インデックスへの影響

### UUIDv4 の問題

UUIDv4 は完全にランダムな値を生成する。B-Tree インデックスでは値の大小関係でノードを配置するため、ランダムな INSERT はツリー全体にページ分割を引き起こす。結果としてインデックスが断片化し、INSERT 性能とストレージ効率が劣化する。

### UUIDv7 が解決する仕組み

UUIDv7 は先頭 48 ビットにミリ秒精度の Unix タイムスタンプを格納する（RFC 9562, 2024）。新しいレコードは常にインデックスの末尾付近に挿入されるため、AUTO_INCREMENT と同等の局所性を維持できる。ランダム部分は残り 74 ビット（rand_a 12 ビット + rand_b 62 ビット）に収まり、同一ミリ秒内の衝突を回避する。

### パフォーマンス特性まとめ

| 指標 | AUTO_INCREMENT | UUIDv4 | UUIDv7 |
|------|---------------|--------|--------|
| INSERT の局所性 | ◎ 常に末尾追記 | ✕ ランダム位置 | ○ ほぼ末尾追記 |
| インデックス断片化 | ほぼなし | 深刻 | 軽微 |
| ストレージ | 8 bytes | 16 bytes | 16 bytes |
| レンジスキャン（時系列） | ◎ | ✕ | ○ |

## 内部 ID と外部 ID の分離パターン

主キーをそのまま API や URL に公開すると、セキュリティリスクとシステム内部構造の露出を招く。内部 ID と外部 ID を分離することでこれらの問題を回避する。

### テーブル設計例

```sql
-- PostgreSQL 18+: ネイティブ uuidv7() を使用
-- PostgreSQL 13-17: CREATE EXTENSION IF NOT EXISTS pg_uuidv7; を実行し uuid_generate_v7() を使用

CREATE TABLE orders (
    -- 内部 ID: DB 内部の結合・参照に使用
    id          UUID PRIMARY KEY DEFAULT uuidv7(),  -- PG18+ ネイティブ（PG13-17 は uuid_generate_v7()）
    -- 外部 ID: API レスポンスや URL に公開（アプリケーション層で生成）
    public_id   VARCHAR(22) NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_public_id ON orders (public_id);
```

### 外部 ID の生成方式

| 方式 | 長さ | 特徴 |
|------|------|------|
| Base62 エンコード | 22文字程度 | URL safe、UUIDv7 を Base62 変換 |
| NanoID | 21文字（デフォルト） | カスタムアルファベット対応、暗号学的乱数 |

### 使い分け

- **内部 ID（主キー）**: JOIN、外部キー参照、DB 内部のリレーションに使用。API レスポンスには含めない
- **外部 ID（public_id）**: REST API のパス（`/orders/{public_id}`）、URL、ユーザー向け表示に使用。アプリケーション層で Base62 または NanoID を生成し INSERT 時にセットする

## 言語別 UUIDv7 生成

### Go

```go
import "github.com/google/uuid" // v1.6+、RFC 9562 準拠

id, err := uuid.NewV7()
```

### TypeScript

```typescript
import { v7 as uuidv7 } from 'uuid'

const id = uuidv7()
```

### Python

```python
import uuid  # Python 3.14+ 標準ライブラリ

id = uuid.uuid7()
```

### Java

```java
// Java 公式は UUIDv7 未対応（サードパーティライブラリはサプライチェーン懸念で非推奨）
// DB 側で生成するか、Kotlin 等の対応済み言語を利用する
```

### Rust

```rust
use uuid::Uuid; // uuid クレート v1.7+, features = ["v7"] を有効にする

let id = Uuid::now_v7();
```

### Kotlin

```kotlin
import kotlin.uuid.Uuid

val id: Uuid = Uuid.generateV7() // Kotlin 2.0+ 標準ライブラリ
```

## PostgreSQL での UUIDv7 サポート

| 方式 | 対象バージョン | 備考 |
|------|--------------|------|
| ネイティブ `uuidv7()` 関数 | PG18+ | 拡張不要。PostgreSQL コアに組み込み |
| `pg_uuidv7` 拡張 | PG13–17 | `CREATE EXTENSION pg_uuidv7;` が必要。関数名は `uuid_generate_v7()` |
| アプリケーション層で生成 | 全バージョン | DB 関数に依存しない。INSERT 時にアプリで生成する |

### PostgreSQL 18+（ネイティブ）

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuidv7()
);
```

### PostgreSQL 13–17（pg_uuidv7 拡張）

```sql
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v7()
);
```

### アプリケーション層で生成する場合

DEFAULT 句は使わず、INSERT 時にアプリケーション側で UUIDv7 を生成してセットする。

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY
);
```

## 連番 ID のセキュリティリスク

### IDOR（Insecure Direct Object Reference）

連番 ID を API や URL で公開すると、ID を ±1 するだけで他ユーザーのリソースにアクセスを試行できる。

```
GET /api/orders/1023  → 自分の注文
GET /api/orders/1024  → 他人の注文（認可チェックが不十分なら閲覧可能）
```

認可チェックを正しく実装していても、連番 ID の公開自体が攻撃面を広げる。

### ビジネスメトリクスの漏洩

連番 ID の差分から業務情報を推測できる。

- ユーザー ID の差分 → 登録者数の推定
- 注文 ID の差分 → 注文件数の推定
- 特定期間の ID 範囲 → 成長率の推定

競合他社や攻撃者に対して、本来非公開のビジネス指標を露出させるリスクがある。

### 対策

1. **外部 ID の分離**: 主キーとは別に推測不能な public_id を公開する（上記の分離パターンを参照）
2. **UUIDv7 の採用**: 主キー自体を推測不能にする（連番 ID の完全な代替）
3. **認可チェックの徹底**: ID 戦略に関わらず、リソースアクセス時の認可チェックは必須
