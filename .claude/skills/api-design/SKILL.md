---
name: api-design
description: API設計スキル。REST API設計、エンドポイント定義、レスポンス形式、バージョニングの依頼時に使用する。プロジェクト固有のAPI設計方針を提供する。
---

# API 設計 Skill

プロジェクト固有の API 設計方針。HTTP/REST の一般知識は省略する。

## エンドポイント設計

### ベース URL 戦略

プロジェクトに応じて以下のいずれかを選択する:

| 方式 | 例 | 適するケース |
|------|-----|------------|
| サブドメイン | `api.example.com/v1/users` | API を独立したサービスとしてデプロイする場合。CORS 設定・SSL 証明書・スケーリングを API 単独で管理できる |
| パスプレフィックス | `example.com/api/v1/users` | フロントエンドと同一オリジンで提供する場合。CORS 不要でシンプル |

- プロジェクト開始時にどちらを採用するか決定し、`wiki/pages/architecture/architecture.md` に記録する
- サブドメイン方式の場合、CORS の許可オリジン設定を忘れないこと（`security` skill 参照）

### URL 設計

- リソース名は複数形・kebab-case: `/v1/order-items`
- ネストは2階層まで: `/v1/users/{id}/orders`
- 3階層以上はフラットにする: `/v1/orders?user_id={id}`
- 動詞は使わない（HTTP メソッドで表現する）

### HTTP メソッド

| メソッド | 用途 | 冪等性 | 安全性 |
|---------|------|--------|-------|
| GET | リソース取得 | Yes | Yes |
| POST | リソース作成 | No | No |
| PUT | リソース全体更新 | Yes | No |
| PATCH | リソース部分更新 | No | No |
| DELETE | リソース削除 | Yes | No |

## レスポンス形式

### 成功レスポンス

```json
{
  "data": { ... },
  "meta": {
    "request_id": "uuid"
  }
}
```

### 一覧レスポンス（ページベース）

```json
{
  "data": [ ... ],
  "meta": {
    "total": 100,
    "page": 1,
    "per_page": 20,
    "total_pages": 5,
    "request_id": "uuid"
  }
}
```

### 一覧レスポンス（オフセットベース）

```json
{
  "data": [ ... ],
  "meta": {
    "total": 100,
    "offset": 40,
    "limit": 20,
    "request_id": "uuid"
  }
}
```

### エラーレスポンス

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "ユーザー向けメッセージ",
    "details": [
      {
        "field": "email",
        "message": "メールアドレスの形式が不正です"
      }
    ]
  },
  "meta": {
    "request_id": "uuid"
  }
}
```

## ステータスコード

| コード | 用途 |
|--------|------|
| 200 | 成功（GET, PUT, PATCH） |
| 201 | 作成成功（POST） |
| 204 | 成功・レスポンスボディなし（DELETE） |
| 400 | バリデーションエラー |
| 401 | 認証エラー |
| 403 | 認可エラー |
| 404 | リソース未検出 |
| 409 | 競合（重複作成等） |
| 422 | 処理不能（ビジネスロジックエラー） |
| 429 | レート制限超過 |
| 500 | サーバー内部エラー |

## バージョニング

- URL パスにバージョンを含める: `/v1/users`
- サブドメイン方式: `api.example.com/v1/users`
- パスプレフィックス方式: `example.com/api/v1/users`
- 破壊的変更時にバージョンを上げる
- 旧バージョンは非推奨期間を設けてから廃止する

## ページネーション

| 方式 | クエリパラメータ | 適するケース |
|------|----------------|------------|
| ページベース | `?page=1&per_page=20` | 管理画面など総ページ数を表示する UI。ページ番号での直接ジャンプが必要な場合 |
| オフセットベース | `?offset=0&limit=20` | スキップ件数を直接指定する API。DB の OFFSET/LIMIT と 1:1 で対応させたい場合 |
| カーソルベース | `?cursor=xxx&limit=20` | 大量データのスクロール読み込み。リアルタイム追加されるフィードなど、一貫性が求められる場合 |

- プロジェクトで採用する方式を統一し、`wiki/pages/architecture/architecture.md` に記録する
- `per_page` / `limit` の上限を設定する（最大100等）
- ページベースとオフセットベースは `total` を返す。カーソルベースは `has_next` を返す
- オフセットベースの `offset` は 0 始まり

## 認証・認可

- Bearer トークンを使用する: `Authorization: Bearer <token>`
- API キーは `X-API-Key` ヘッダーで受け取る
- 認可は RBAC で制御する（`security` skill 参照）

## OpenAPI 仕様

- OpenAPI 3.x 形式で API 仕様を定義する
- フレームワークが対応している場合はコードから自動生成を優先する:
  - TypeScript: `@nestjs/swagger`（NestJS）、`hono-zod-openapi`（Hono）、`tsoa`
  - Python: `FastAPI`（Pydantic モデルから自動生成）、`drf-spectacular`（Django REST Framework）
- 自動生成できない場合は手書きの `openapi.yaml` を管理する
- CI で OpenAPI 仕様とコードの乖離を検出する仕組みを入れる

## ドキュメント出力先

- API 仕様書 → `raw/issues/` の該当 Issue ディレクトリ
- 確定した API 仕様 → `wiki/pages/architecture/architecture.md` に反映
- OpenAPI 定義ファイルはリポジトリルートまたは `docs/` 配下で管理する
