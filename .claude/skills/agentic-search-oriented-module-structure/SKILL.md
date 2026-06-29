---
name: agentic-search-oriented-module-structure
description: Agentic Search最適化モジュール構造。新規プロジェクトで機能単位のファイル凝集・テスト隣接配置・AIエージェント検索最適化を実現する。
user_invocable: false
---

# Agentic Search最適化モジュール構造

新規プロジェクトのディレクトリ構造として、AIエージェントの検索効率を最大化する機能単位（Feature-based）のモジュール構成を推奨する。

## 適用条件

- **新規プロジェクトのみ**適用する
- 既存プロジェクト（ソースファイル100個以上）には適用しない。言語を問わず、プロジェクトルートから再帰的にソースファイル数をカウントする
- 既存ルールとのコンフリクトで混乱が生じるため
- **既存プロジェクトへの AI Driven Development 導入時**: 既存のディレクトリ構成・命名規則・使用ツールを優先する。本スキルの構造を強制せず、既存の慣習に合わせる

## 推奨構造

```
src/
  features/
    login/
      login-view.tsx
      login-usecase.ts
      login-usecase.test.ts
      login-api.ts
    dashboard/
      dashboard-view.tsx
      dashboard-usecase.ts
      dashboard-usecase.test.ts
  shared/
    ui/          # 3+ 機能で共有される UI コンポーネント
    utils/       # 汎用ユーティリティ
    types/       # 共有型定義
```

## 設計原則

### 1. 機能凝集（Feature Cohesion）

1機能 = 1ディレクトリ。View, UseCase, API, Testをすべて同一ディレクトリに配置する。水平スライス（Controllers/, Services/, Models/）ではなく垂直スライスで分割する。

### 2. テスト隣接配置（Collocated Tests）

`*.test.ts` をソースコードと同じディレクトリに配置する。`__tests__/` や `tests/` への分離は避ける。`ls` 一回でテスト有無を確認可能にする。

### 3. Agentic Search 最適化

AIエージェントが得意な `grep`, `glob`, `cat` での検索効率を最大化する。

- **Grep-able**: named export強制、一貫したエラー型
- **Glob-able**: `src/features/login/*` で機能の全ファイル取得可能
- **ジャンプ最小化**: 1機能を理解するのに複数ディレクトリを横断しない

### 4. shared/ の昇格ルール

最初は機能ディレクトリ内に配置する。3つ以上の機能で共有される場合に `shared/` に昇格する。早すぎる共通化を避ける。

## ファイル命名規則

| ファイル種別 | 命名パターン | 例 |
|-------------|-------------|-----|
| View/Component | `{feature}-view.tsx` | `login-view.tsx` |
| UseCase/Logic | `{feature}-usecase.ts` | `login-usecase.ts` |
| API通信 | `{feature}-api.ts` | `login-api.ts` |
| 型定義 | `{feature}-types.ts` | `login-types.ts` |
| テスト | `{feature}-{layer}.test.ts` | `login-usecase.test.ts` |
| スタイル | `{feature}-styles.ts` | `login-styles.ts` |

## 言語別の適用

TypeScript/Reactを例としているが、他言語でも同じ原則を適用する:

- **Go**: `internal/features/login/`, `internal/shared/`
- **Kotlin**: `src/main/kotlin/features/login/`, `src/main/kotlin/shared/`
- **Python**: `src/features/login/`, `src/shared/`
- **Rust**: `src/features/login/`, `src/shared/`

各言語の命名規則（`.claude/rules/languages/` 参照）に従ってファイル名を調整する。
