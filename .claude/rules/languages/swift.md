---
paths: "**/*.swift, **/Package.swift, **/Package.resolved"
---

# Swift 固有ルール

## コード品質

### SwiftLint（リンター）

- **SwiftLint** を標準リンターとして使用する
- 設定ファイル: `.swiftlint.yml`
- CI でリントチェックを実行する

### swift-format（フォーマッター）

- **swift-format**（Apple 公式）を標準フォーマッターとして使用する
- 設定ファイル: `.swift-format`（必要に応じて）
- CI でフォーマットチェックを実行する

### 型安全性

- `Any` / `AnyObject` の使用は最小限にし、プロトコルやジェネリクスを優先する
- 強制アンラップ（`!`）は `IBOutlet` 以外で使用禁止する
- `as!` は使わず `as?` で安全にキャストする
- `@objc` は Objective-C 互換が必要な場合のみ使用する
- `// swiftlint:disable` は理由をコメントで残す

### 複雑度

- 循環的複雑度: **10 以下**
- 1関数の行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | PascalCase（型と一致） | `UserService.swift` |
| 変数・関数 | camelCase | `getUserById` |
| クラス・構造体・列挙型 | PascalCase | `UserService` |
| プロトコル | PascalCase（`-able`, `-ible`, `-ing` サフィックス推奨） | `Codable`, `UserProviding` |
| 定数 | camelCase（型プロパティは UPPER_SNAKE_CASE 不要） | `let maxRetryCount = 3` |
| Enum ケース | camelCase | `UserRole.admin` |
| 型パラメータ | PascalCase | `Element`, `Key` |

### Swift 固有の命名慣習

- Bool プロパティは `is`, `has`, `can`, `should` プレフィックスを使う
- ファクトリメソッドは `make` プレフィックス: `makeUserView()`
- プロトコルは能力を表す名前にする: `Equatable`, `Hashable`

## エラーハンドリング

### カスタムエラー

```swift
enum AppError: LocalizedError {
    case notFound(resource: String)
    case validation(message: String)
    case unauthorized
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let resource): return "\(resource) が見つかりません"
        case .validation(let message): return "入力エラー: \(message)"
        case .unauthorized: return "認証が必要です"
        case .server(let code, let message): return "サーバーエラー (\(code)): \(message)"
        }
    }
}
```

### ルール

- `do-catch` で具体的なエラーパターンをマッチする
- `try?` は結果を無視してよい場合のみ使用する
- `try!` の使用を禁止する
- `Result<Success, Failure>` 型を非同期処理のコールバックで活用する
- `async/await`（Swift 5.5+）でエラーを `throws` で伝播する
- `defer` でリソースのクリーンアップを行う

## 依存関係管理

- **パッケージマネージャー**: Swift Package Manager（SPM）を使用する
- **Package.resolved**: 必ずコミットする
- **バージョン指定**: `.exact("1.2.3")` で固定バージョンを指定する（サプライチェーン攻撃対策）
- **CocoaPods / Carthage**: 新規プロジェクトでは SPM を優先する
- **プラットフォーム指定**: `platforms: [.iOS(.v16)]` で最低バージョンを明示する

## テスト

- テストファイル: `*Tests.swift`
- テストメソッド名: `func test_getUserByID_notFound_throwsError()`
- **XCTest** を使用する（Swift Testing framework も可）
- `XCTAssertThrowsError` で例外テストを行う
- UI テスト: `XCUITest` を使用する
