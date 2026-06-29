---
paths: "**/*.kt, **/*.kts, **/build.gradle.kts, **/libs.versions.toml"
---

# Kotlin 固有ルール

## コード品質

### detekt（静的解析）

- **detekt** を静的解析ツールとして使用する
- 設定ファイル: `detekt.yml`
- CI で静的解析を実行する

### ktlint（フォーマッター + リンター）

- **ktlint** をフォーマッターおよびリンターとして使用する
- Kotlin 公式コーディング規約に準拠する

### 型安全性

- Nullable 型は明示的に `?` を付与し、安全呼び出し `?.` またはスコープ関数で処理する
- `!!`（非 null アサーション）の使用を禁止する
- プラットフォーム型（Java 相互運用時の `!` 型）は明示的に Nullable / NonNull を指定する
- `Any` のキャストは `as?` で安全キャストし、`as` の直接使用を避ける
- `@Suppress` は理由をコメントで残す

### 複雑度

- 循環的複雑度（Cyclomatic Complexity）: **10 以下**
- 1関数の行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | PascalCase（クラスと一致） | `UserService.kt` |
| 変数・関数 | camelCase | `getUserById` |
| クラス | PascalCase | `UserService` |
| インターフェース | PascalCase（I プレフィックス不要） | `UserRepository` |
| 定数（companion object / top-level） | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Enum | PascalCase（メンバーも UPPER_SNAKE_CASE） | `UserRole.ADMIN` |
| パッケージ | すべて小文字、ドット区切り | `com.example.user` |
| 拡張関数 | camelCase | `String.toSlug()` |
| バッキングプロパティ | `_` プレフィックス | `_internalState` |

## エラーハンドリング

### カスタム例外

```kotlin
open class AppException(
    message: String,
    val code: String,
    val statusCode: Int = 500,
    val isOperational: Boolean = true,
    cause: Throwable? = null
) : RuntimeException(message, cause)
```

### sealed class によるエラー表現

```kotlin
sealed class Result<out T> {
    data class Success<T>(val data: T) : Result<T>()
    data class Failure(val error: AppException) : Result<Nothing>()
}
```

### ルール

- `catch (e: Exception)` のような広すぎる catch は避ける
- `catch` には具体的な例外クラスを指定する
- `runCatching` / `Result` 型を活用し、例外の伝播を制御する
- `!!` による NullPointerException の発生を防ぐ（`?.` / `?:` / `let` を使う）
- Coroutine のエラーは `CoroutineExceptionHandler` または `supervisorScope` で処理する
- `use` 拡張関数でリソースのクリーンアップを行う（`Closeable` の自動クローズ）

## 依存関係管理

- **ビルドツール**: Gradle（Kotlin DSL `build.gradle.kts`）を使用する
- **lockファイル**: `gradle.lockfile` を有効化しコミットする（`./gradlew dependencies --write-locks`）
- **バージョン指定**: バージョンカタログ（`gradle/libs.versions.toml`）で一元管理する
- **バージョン固定**: 動的バージョン（`+`, `latest.release`）を使わない。サプライチェーン攻撃の影響を最小化するため
- **依存スコープ**: `implementation` / `api` / `testImplementation` を適切に分離する
- **BOM**: Spring Boot / Kotlin 等の BOM（`platform()`）でバージョン整合性を担保する

### UUIDv7

- UUIDv7 生成には Kotlin 標準ライブラリ（Kotlin 2.0+）を使用する: `kotlin.uuid.Uuid.generateV7()`

## テスト

- テストファイル: `*Test.kt` / `*Spec.kt`
- テスト関数名: `@Test fun 'メソッド名 - 条件 - 期待結果'()` またはバッククォートで日本語記述可
