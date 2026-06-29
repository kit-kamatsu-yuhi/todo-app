---
paths: "**/*.rs, **/Cargo.toml, **/Cargo.lock"
---

# Rust 固有ルール

## コード品質

### clippy（リンター）

- **clippy** を標準リンターとして使用する
- `#![warn(clippy::all, clippy::pedantic)]` を有効化する
- CI で `cargo clippy -- -D warnings` を実行する

### rustfmt（フォーマッター）

- **rustfmt** を標準フォーマッターとして使用する
- 設定ファイル: `rustfmt.toml`（必要に応じて）
- CI でフォーマットチェックを実行する

### 型安全性

- `unsafe` ブロックは最小限にし、使用時はコメントで安全性の根拠を示す
- `unwrap()` / `expect()` はテストコードのみ許可する（プロダクションコードでは `?` 演算子を使う）
- `as` によるキャストは `TryFrom` / `TryInto` で置き換える
- `Box<dyn Any>` の使用を避け、ジェネリクスやトレイトオブジェクトを使う

### 複雑度

- 循環的複雑度: **10 以下**
- 1関数の行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | snake_case | `user_service.rs` |
| 変数・関数 | snake_case | `get_user_by_id` |
| 構造体・列挙型・トレイト | PascalCase | `UserService` |
| 定数 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| モジュール | snake_case | `data_processing` |
| 型パラメータ | 大文字1文字 or PascalCase | `T`, `Item` |
| ライフタイム | 短い小文字 | `'a`, `'ctx` |
| マクロ | snake_case! | `vec!`, `println!` |

## エラーハンドリング

### カスタムエラー

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found: {0}")]
    NotFound(String),
    #[error("validation error: {0}")]
    Validation(String),
    #[error("internal error: {0}")]
    Internal(#[from] anyhow::Error),
}
```

### ルール

- `Result<T, E>` を返り値に使い、`?` 演算子でエラーを伝播する
- `thiserror` でカスタムエラー型を定義する
- `anyhow` はアプリケーション層のエラーハンドリングに使用する（ライブラリでは使わない）
- `panic!` はプログラムの不変条件違反のみに限定する
- `Option` と `Result` を適切に使い分ける（`Option` は値の有無、`Result` は操作の成否）
- `Drop` トレイトでリソースのクリーンアップを行う

## 依存関係管理

- **パッケージマネージャー**: Cargo（`Cargo.toml` / `Cargo.lock`）を使用する
- **Cargo.lock**: バイナリクレートでは必ずコミットする。ライブラリクレートではコミットしない
- **バージョン指定**: `=1.2.3` で固定バージョンを指定する（サプライチェーン攻撃対策）
- **features**: 必要な feature のみ有効化し、不要な依存を減らす
- **workspace**: 複数クレート構成では Cargo workspace を使用する
- **依存監査**: `cargo audit` で脆弱性を定期的にチェックする

### UUIDv7

- UUIDv7 生成には `uuid` クレート（v1.7+）を使用する: `Uuid::now_v7()`
- `Cargo.toml` で `v7` feature を有効にする: `uuid = { version = "=1.7.0", features = ["v7"] }`

## テスト

- テスト: 同一ファイル内の `#[cfg(test)] mod tests` に記述する
- Integration テスト: `tests/` ディレクトリに配置する
- テスト関数名: `#[test] fn get_user_by_id_not_found_returns_error()`
- `#[should_panic]` はパニックテストのみに使用する
- プロパティベーステスト: `proptest` クレートを推奨する
