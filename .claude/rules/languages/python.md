---
paths: "**/*.py, **/*.pyi, **/pyproject.toml, **/requirements*.txt"
---

# Python 固有ルール

## コード品質

### ruff（リンター + フォーマッター）

- **ruff** をリンターおよびフォーマッターとして使用する
- 設定: `pyproject.toml` の `[tool.ruff]` セクション

### mypy（型チェック）

- **mypy** で静的型チェックを行う
- strict モードを有効にする
- 型アノテーションを関数シグネチャに付与する

### 複雑度

- 循環的複雑度: **10 以下**
- 1関数の行数: **50行以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | snake_case | `user_service.py` |
| 変数・関数 | snake_case | `get_user_by_id` |
| クラス | PascalCase | `UserService` |
| 定数 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| モジュール | snake_case | `data_processing` |
| パッケージ | snake_case（短く） | `utils` |
| プライベート | `_` プレフィックス | `_internal_method` |

## エラーハンドリング

### カスタム例外

```python
class AppError(Exception):
    def __init__(self, message: str, code: str, status_code: int = 500):
        super().__init__(message)
        self.code = code
        self.status_code = status_code
```

### ルール

- `except Exception` のような広すぎる catch は避ける
- `except` には具体的な例外クラスを指定する
- `finally` でリソースのクリーンアップを行う（または `with` 文を使う）
- ログには `logger.exception()` を使いスタックトレースを記録する

## 依存関係管理

- **パッケージマネージャー**: uv を使用する
- **パッケージ管理**: `pyproject.toml` で管理する
- **lockファイル**: `uv.lock` を必ずコミットする
- **仮想環境**: uv でプロジェクトごとに仮想環境を作成する
- **バージョン指定**: バージョンを固定する（`~=` を使わない。サプライチェーン攻撃の影響を最小化するため）

### UUIDv7

- UUIDv7 生成には Python 標準ライブラリ（Python 3.14+）を使用する: `import uuid; uuid.uuid7()`
- Python 3.13 以前の場合はアプリケーション層で DB 側生成を利用するか、`uuid6` パッケージをフォールバックとして使用する

## テスト

- テストファイル: `test_*.py` / `*_test.py`
- テスト関数名: `def test_関数名_条件_期待結果():`
