---
name: db-design
description: DB設計スキル。テーブル設計・正規化・インデックス設計・スキーマ変更の依頼時に使用する。プロジェクト固有のDB設計方針を提供する。
---

# DB 設計 Skill

プロジェクト固有のデータベース設計方針。一般的なRDB知識は省略する。

## 設計プロセス

1. **要件からエンティティを抽出** — ドメインモデルを特定する
2. **ER図を作成** — Mermaid erDiagram で記述する（`uml` skill 参照）
3. **正規化** — 第3正規形（3NF）を基本とする
4. **非正規化の検討** — パフォーマンス要件がある場合のみ、根拠を記録して非正規化する
5. **インデックス設計** — クエリパターンに基づいて設計する
6. **マイグレーション計画** — `/db-migrate` で安全に適用する

## 正規化の方針

- 3NF を基本とする
- 非正規化する場合は以下を記録する:
  - 対象テーブル・カラム
  - 非正規化の理由（クエリパフォーマンス、読み取り頻度等）
  - トレードオフ（データ整合性リスク、更新コスト）

## 命名規約

| 対象 | 規則 | 例 |
|------|------|-----|
| テーブル名 | snake_case・複数形 | `users`, `order_items` |
| カラム名 | snake_case | `created_at`, `user_id` |
| 主キー | `id` | `id` |
| 外部キー | `{参照テーブル単数形}_id` | `user_id`, `order_id` |
| インデックス | `idx_{テーブル}_{カラム}` | `idx_users_email` |
| ユニーク制約 | `uniq_{テーブル}_{カラム}` | `uniq_users_email` |

## 共通カラム

すべてのテーブルに以下のカラムを含める:

### UUIDv7（新規プロジェクトのデフォルト）

```sql
id          UUID PRIMARY KEY DEFAULT uuid_generate_v7()  -- pg_uuidv7 拡張が必要
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

UUIDv7（RFC 9562, 2024）は時間ソート可能かつ分散生成に対応し、B-Tree インデックスの局所性を維持する。新規プロジェクトでは UUIDv7 を標準の主キーとして採用する。PostgreSQL での利用方法は `references/id-strategy.md` を参照。

### BIGINT ID（既存プロジェクト・閉じた内部システム向け）

```sql
id          BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY
created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
```

既存プロジェクトで BIGINT を使用している場合や、外部公開しない閉じた内部システムでは引き続き BIGINT を使用して構わない。

### 外部公開 ID（API・URL 向け）

主キーを直接 API や URL に公開せず、別カラムで外部 ID を管理する。

```sql
public_id   VARCHAR(22) NOT NULL UNIQUE
```

Base62 エンコードまたは NanoID で生成し、`/orders/{public_id}` のように使用する。

### ID 型の選定基準

| 基準 | UUIDv7 | BIGINT |
|------|--------|--------|
| 新規プロジェクトのデフォルト | **採用** | — |
| 既存プロジェクト・閉じた内部システム | — | **採用** |
| 分散システムで生成する | **採用** | — |
| JOIN のパフォーマンス重視 | ○（時間ソートで局所性維持） | **採用**（8 bytes） |
| ストレージ効率重視 | △（16 bytes） | **採用**（8 bytes） |

- UUIDv4 は B-Tree インデックスの断片化を引き起こすため、新規プロジェクトでは非推奨
- プロジェクト内で ID 型が混在しても構わないが、テーブルごとに選定理由を記録する
- 論理削除が必要な場合は `deleted_at TIMESTAMPTZ` を追加する
- 外部キーの型は参照先の主キーと一致させる

### 連番 ID のセキュリティリスク

連番 ID を外部公開すると以下のリスクがある:

- **IDOR 脆弱性**: ID を ±1 するだけで他ユーザーのリソースにアクセスを試行できる
- **ビジネスメトリクス漏洩**: ID の差分から登録者数や注文件数を推測できる

詳細は `references/id-strategy.md` を参照。

## インデックス設計

- WHERE / JOIN / ORDER BY で頻繁に使われるカラムにインデックスを張る
- カーディナリティが低いカラム（boolean等）への単独インデックスは避ける
- 複合インデックスはカーディナリティが高いカラムを先にする
- カバリングインデックスを検討する

## 型の選定

| 用途 | 推奨型 | 避ける型 |
|------|--------|---------|
| 主キー（新規プロジェクト） | `UUID DEFAULT uuid_generate_v7()`（pg_uuidv7 拡張） | `SERIAL`（レガシー） |
| 主キー（既存・閉じた内部システム） | `BIGINT GENERATED ALWAYS AS IDENTITY` | `SERIAL`（レガシー） |
| 外部公開 ID | 別カラム `public_id VARCHAR(22)` + Base62/NanoID | 主キーをそのまま公開 |
| 金額 | `NUMERIC(precision, scale)` | `FLOAT`, `DOUBLE` |
| 日時 | `TIMESTAMPTZ` | `TIMESTAMP`（タイムゾーンなし） |
| 真偽値 | `BOOLEAN` | `TINYINT`, `CHAR(1)` |
| 長文 | `TEXT` | `VARCHAR(MAX)` |
| 列挙 | アプリケーション層で管理 | DB の ENUM 型 |

## ドキュメント出力先

- ER図・スキーマ定義 → `raw/issues/` の該当 Issue ディレクトリ
- 確定したスキーマ → `wiki/pages/architecture/architecture.md` に反映
