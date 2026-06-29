---
paths: "**/*.go, **/go.mod, **/go.sum"
---

# Go 固有ルール

## コード品質

### golangci-lint（リンター）

- **golangci-lint** を統合リンターとして使用する
- 設定ファイル: `.golangci.yml`
- 有効化推奨のリンター: `errcheck`, `govet`, `staticcheck`, `unused`, `gosimple`, `ineffassign`
- CI でリントチェックを実行する

### gofmt / goimports（フォーマッター）

- **gofmt** を標準フォーマッターとして使用する
- **goimports** で import 文の整理も行う
- CI でフォーマットチェックを実行する

### 型安全性

- `interface{}` / `any` の使用は最小限にし、ジェネリクス（Go 1.18+）を優先する
- 型アサーションは `value, ok := x.(Type)` の2値パターンを使う
- `unsafe` パッケージの使用を禁止する（やむを得ない場合はコメントで理由を残す）

### 複雑度

- 循環的複雑度: **10 以下**
- 1関数の行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | snake_case | `user_service.go` |
| 変数・関数（exported） | PascalCase | `GetUserByID` |
| 変数・関数（unexported） | camelCase | `getUserByID` |
| インターフェース | PascalCase（`-er` サフィックス推奨） | `Reader`, `UserRepository` |
| 定数 | PascalCase（exported）/ camelCase（unexported） | `MaxRetryCount` |
| パッケージ | すべて小文字、短く | `user`, `auth` |
| レシーバー | 1〜2文字の短い名前 | `func (s *Service) Get()` |

### Go 固有の命名慣習

- 頭字語は全大文字: `ID`, `HTTP`, `URL`（`Id`, `Http` は不可）
- ゲッターに `Get` プレフィックスは付けない: `user.Name()`（`user.GetName()` は不可）
- パッケージ名と型名の重複を避ける: `user.User` ではなく `user.Info` や `user.Record`

## エラーハンドリング

### カスタムエラー

```go
type AppError struct {
    Message    string
    Code       string
    StatusCode int
    Err        error
}

func (e *AppError) Error() string { return e.Message }
func (e *AppError) Unwrap() error { return e.Err }
```

### ルール

- エラーは必ずチェックする（`_ = doSomething()` 禁止）
- `errors.Is()` / `errors.As()` でエラー判定する（`==` 比較は避ける）
- エラーのラップは `fmt.Errorf("context: %w", err)` を使う
- `panic` は初期化時の致命的エラーのみに限定する
- `defer` でリソースのクリーンアップを行う
- sentinel エラーは `var ErrNotFound = errors.New("not found")` で定義する

## 依存関係管理

- **モジュール管理**: Go Modules（`go.mod` / `go.sum`）を使用する
- **go.sum**: 必ずコミットする
- **バージョン指定**: `go get package@v1.2.3` で固定バージョンを指定する
- **最小バージョン選択**: Go の MVS（Minimum Version Selection）に従う
- **依存整理**: `go mod tidy` で未使用依存を定期的に削除する
- **ベンダリング**: 必要に応じて `go mod vendor` を使用する

### UUIDv7

- UUIDv7 生成には `github.com/google/uuid`（v1.6+）を使用する: `uuid.NewV7()`

## テスト

- テストファイル: `*_test.go`（同一パッケージ内）
- テスト関数名: `func TestGetUserByID_NotFound_ReturnsError(t *testing.T)`
- テーブル駆動テストを積極的に使用する
- `testify` の使用を推奨（`assert` / `require`）
- ベンチマーク: `func BenchmarkXxx(b *testing.B)`
