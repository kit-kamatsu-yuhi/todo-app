---
paths: "**/*.ts, **/*.tsx, **/*.mts, **/*.cts, **/tsconfig*.json, **/package.json"
---

# TypeScript 固有ルール

## コード品質

### Vite+（推奨ツールチェーン）

**Vite+** を統合ツールチェーンとして推奨する。lint/fmt/test/build/run を `vp` コマンドで統一し、設定は `vite.config.ts` に集約する。

| コマンド | 用途 | 置き換え対象 |
|----------|------|-------------|
| `vp lint` | リンター（oxlint） | ESLint, Biome linter |
| `vp fmt` | フォーマッター（oxfmt） | Prettier, Biome formatter |
| `vp check` | lint + fmt + 型チェックを一括実行 | — |
| `vp test` | テストランナー（Vitest） | vitest CLI |
| `vp build` | プロダクションビルド（Rolldown） | vite build |
| `vp run` | タスクランナー（キャッシュ付き） | pnpm run, Turborepo |
| `vp env` | Node.js バージョン管理 | nvm, fnm, volta |
| `vpx` | パッケージバイナリ実行 | npx, pnpm dlx |

- Vite+ 単体で pnpm/husky/nvm の代替として開発環境を構築可能
- Vite+ が廃れた場合に備え、Biome（`biome.json`）や oxfmt 単体も併記する
- プロジェクト内で Biome と Vite+ が混在する場合は、各サブプロジェクトで統一する
- CI でフォーマットチェックを実行する

### Biome（代替ツールチェーン）

Vite+ の代替として **Biome** も使用可能:

- 設定ファイル: `biome.json`
- 文字列リテラルはシングルクォート（`'`）を使用する
- セミコロンは付けない（`semicolons: asNeeded`）

### 型安全性

- TypeScript strict モードを有効にする
- `any` 型の使用を禁止する（`unknown` を使用）
- 型アサーション（`as`）は最小限にする
- `@ts-ignore` / `@ts-expect-error` は理由をコメントで残す

### 複雑度

- 循環的複雑度（Cyclomatic Complexity）: **10 以下**
- 1関数の行数: **50行以下** を目安とする
- ネストの深さ: **3階層以下** を目安とする

## 命名規則

| 対象 | 規則 | 例 |
|------|------|-----|
| ファイル名 | kebab-case | `user-service.ts` |
| 変数・関数 | camelCase | `getUserById` |
| クラス | PascalCase | `UserService` |
| インターフェース | PascalCase（I プレフィックス不要） | `UserRepository` |
| 型エイリアス | PascalCase | `UserId` |
| 定数 | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| Enum | PascalCase（メンバーも PascalCase） | `UserRole.Admin` |
| コンポーネント | PascalCase | `UserProfile.tsx` |

## エラーハンドリング

### カスタムエラー型

```typescript
class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly statusCode: number,
    public readonly isOperational: boolean = true
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}
```

### エラー分類

| カテゴリ | 説明 | 対応 |
|---------|------|------|
| Operational | 予期されるエラー（入力不正、外部API障害等） | 適切なレスポンスを返す |
| Programming | バグ（型エラー、null参照等） | ログ出力しプロセス再起動 |

### ルール

- `try-catch` は具体的なエラー型で catch する
- エラーは握りつぶさない（空の catch ブロック禁止）
- 非同期処理は必ずエラーハンドリングする
- ユーザー向けメッセージと内部ログメッセージを分離する

## 依存関係管理

- **パッケージマネージャー**: pnpm（推奨）、yarn を使用する
- **lockファイル**: `pnpm-lock.yaml` / `yarn.lock` を必ずコミットする
- **バージョン指定**: バージョンを固定する（キャレット `^` やチルダ `~` を使わない。サプライチェーン攻撃の影響を最小化するため）
- **devDependencies**: 開発用ツール（テスト、リンター等）は `devDependencies` に分離する

### UUIDv7

- UUIDv7 生成には `uuid` パッケージを使用する: `import { v7 as uuidv7 } from 'uuid'`

## テスト

- テストファイル: `*.test.ts` / `*.spec.ts`
- テスト関数名: `describe('関数名', () => { it('should ...') })`
