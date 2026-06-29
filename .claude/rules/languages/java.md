---
paths: "**/*.java, **/build.gradle.kts, **/pom.xml"
---

# Java 固有ルール

## コード品質

### Spotless + Google Java Format（フォーマッター）

- **Spotless** プラグインで **Google Java Format** を適用する
- Gradle: `com.diffplug.spotless` プラグインを使用する
- Maven: `spotless-maven-plugin` を使用する
- CI でフォーマットチェックを実行する

### Error Prone（静的解析）

- **Error Prone** をコンパイル時の静的解析として使用する
- バグパターンの早期検出に活用する
- CI で静的解析を実行する

### 型安全性

- `var` の使用は型が明確な場合のみ許可する
- `Object` 型の使用は最小限にし、ジェネリクスを優先する
- `@Nullable` / `@NonNull` アノテーションで null 安全性を明示する
- `Optional` を返り値に使用する（引数やフィールドには使わない）
- `instanceof` パターンマッチング（Java 16+）を活用する
- `@SuppressWarnings` は理由をコメントで残す

### 複雑度

- 循環的複雑度: **10 以下**
- 1メソッドの行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | PascalCase（クラスと一致） | `UserService.java` |
| 変数・メソッド | camelCase | `getUserById` |
| クラス | PascalCase | `UserService` |
| インターフェース | PascalCase（I プレフィックス不要） | `UserRepository` |
| 定数 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Enum | PascalCase（メンバーは UPPER_SNAKE_CASE） | `UserRole.ADMIN` |
| パッケージ | すべて小文字、ドット区切り | `com.example.user` |
| 型パラメータ | 大文字1文字 | `T`, `E`, `K`, `V` |

## エラーハンドリング

### カスタム例外

```java
public class AppException extends RuntimeException {
    private final String code;
    private final int statusCode;
    private final boolean operational;

    public AppException(String message, String code, int statusCode, boolean operational) {
        super(message);
        this.code = code;
        this.statusCode = statusCode;
        this.operational = operational;
    }

    public AppException(String message, String code, int statusCode, boolean operational, Throwable cause) {
        super(message, cause);
        this.code = code;
        this.statusCode = statusCode;
        this.operational = operational;
    }
}
```

### ルール

- `catch (Exception e)` のような広すぎる catch は避ける
- `catch` には具体的な例外クラスを指定する
- `try-with-resources` でリソースのクリーンアップを行う
- 検査例外は呼び出し元で処理できる場合のみ使用する
- 非検査例外（RuntimeException）はプログラムエラーに使用する
- 例外を握りつぶさない（空の catch ブロック禁止）
- ログには十分なコンテキスト情報を含める

## 依存関係管理

### Gradle（推奨）

- **Gradle Kotlin DSL**（`build.gradle.kts`）を使用する
- バージョンカタログ（`gradle/libs.versions.toml`）で一元管理する
- `gradle.lockfile` を有効化しコミットする
- 動的バージョン（`+`, `latest.release`）を使わない

### Maven

- `pom.xml` の `<dependencyManagement>` でバージョンを一元管理する
- BOM（Bill of Materials）でバージョン整合性を担保する
- バージョン固定: `RELEASE` / `LATEST` を使わない

### 共通

- **バージョン固定**: サプライチェーン攻撃の影響を最小化するため
- **スコープ分離**: `implementation` / `testImplementation`（Gradle）、`compile` / `test`（Maven）
- **脆弱性チェック**: OWASP Dependency Check を CI で実行する

### UUIDv7

- Java 公式が UUIDv7 に対応するまで、Java では UUIDv7 の使用を未サポートとする
- サードパーティライブラリはサプライチェーンアタック懸念のため使用しない
- UUIDv7 が必要な場合はアプリケーション層で別言語（Kotlin 等）の生成結果を利用するか、DB 側で生成する

## テスト

- テストファイル: `*Test.java` / `*Spec.java`
- テストメソッド名: `@Test void getUserById_notFound_throwsException()`
- **JUnit 5** を使用する
- アサーション: **AssertJ** を推奨する
- モック: **Mockito** を使用する
