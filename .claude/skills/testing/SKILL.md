---
name: testing
description: テスト/QA スキル。テスト戦略の相談、テスト設計レビュー、カバレッジ改善の依頼時に使用する。プロジェクト固有のテスト方針・ツール選定・プロパティベーステスト導入を提供する。
---

# テスト/QA Skill

プロジェクト固有のテスト方針。基本ルール（カバレッジ80%、命名規約、テストダブル方針）は `testing` rule 参照。

## プロジェクトのテストツール

| 言語 | テストFW | カバレッジ | プロパティベース |
|------|---------|-----------|----------------|
| TypeScript | Vitest / Jest | c8 / istanbul | fast-check |
| Python | pytest | pytest-cov | Hypothesis |

## プロパティベーステスト

入力空間が広い関数にはプロパティベーステストを検討する。

- 不変条件・逆関数・冪等性などのプロパティを定義する
- 全パターンの網羅が困難な場合に有効

## テストファイル配置

- TypeScript: `*.test.ts` / `*.spec.ts`（ソースファイルと同階層 or `__tests__/`）
- Python: `test_*.py` / `*_test.py`（`tests/` ディレクトリ）
- Kotlin: `*Test.kt` / `*Spec.kt`（`src/test/kotlin/` 配下、本番と同パッケージ構造）

## Kotlin テストツール

| ツール | 用途 |
|-------|------|
| Kotest (FreeSpec) | テストフレームワーク。`FreeSpec` スタイルでネスト記述 |
| MockK | モックライブラリ。`mockk`, `every`, `justRun`, `verify` |
| shouldBe | Kotest のアサーション。`result shouldBe expected` |

### Kotest FreeSpec パターン

```kotlin
class SomeServiceTest : FreeSpec({
    "メソッド名" - {
        "正常系の説明" { /* テスト */ }
        "異常系の説明" { /* テスト */ }
    }
})
```

## セキュリティ関連テストの観点

セキュリティ機能のテストでは以下を網羅する:

- 危険な入力が **チェック対象より前** で拒否されることの検証
- 拒否時にバックエンドリソース（ストレージ等）へのアクセスが発生しないことの検証（`verify(exactly = 0)` パターン）
- 判定優先順序のテスト（例: パストラバーサルが危険拡張子チェックより先に検出される）
- FE/BE 両方で同一の拒否リストが適用されていることの確認

## 手動テストチェックリストの生成

Issue 実装後に `raw/issues/YYYY-MM-DD_<issue番号>/manual-test-checklist.md` を作成する。

含める項目:
1. 新機能の異常系テスト（拒否されるケース）
2. 正常系デグレチェック（影響する全画面）
3. エッジケース（大文字小文字、拡張子なし等）
4. セキュリティ確認（FE/BE 一致、判定順序）
