---
name: codex
description: Codex CLI の共通設定・モデル解決ロジック。codex-* サブエージェントから参照される。直接呼び出しは不要。
---

# Codex CLI 共通設定

codex-design / codex-implement / codex-test / codex-review サブエージェントが参照する共通設定。

## モデル解決の優先順位

1. **環境変数 `CODEX_MODEL`** が設定されている場合はそれを使う（`-m` で明示指定）
2. **`.codex.local.toml`**（プロジェクトルート、.gitignore 済み）の `model` フィールド（codex CLI が自動で読む）
3. 上記いずれも無ければ **codex CLI の default（最新）** に委ねる（`-m` を付けない）

### モデル解決スクリプト

```bash
# CODEX_MODEL が設定されていれば -m で渡す。未設定なら codex CLI の default(最新) に委ねる。
# .codex.local.toml の model は codex CLI 自身が自動で読むため、ここで解決する必要はない。
MODEL_FLAG=""
[ -n "${CODEX_MODEL:-}" ] && MODEL_FLAG="-m ${CODEX_MODEL}"
```

### .codex.local.toml

```toml
# プロジェクトルートに配置（.gitignore 済み）。任意。
# 指定するとそのモデルに固定される。未指定なら codex CLI の default(最新) が使われる。
model = "<固定したいモデル名>"
```

## 共通実行オプション

```bash
codex exec \
  $MODEL_FLAG \
  --full-auto \
  -C "$(pwd)" \
  "$PROMPT"
```

`$MODEL_FLAG` が空のときは `-m` が付かず、codex CLI の default(最新) にフォールバックする。

| オプション | 説明 |
|-----------|------|
| `--full-auto` | サンドボックス内で自動実行 |
| `-C` | 作業ルートディレクトリ |
| `--search` | Web 検索が必要な場合に付与 |

## Codex 可用性とフォールバック

codex-* サブエージェントは codex CLI に処理を委譲するが、codex が使えない環境（未インストール / `codex login` 未実施 / sandbox エラー）でも停止しない。`codex exec` が失敗したら、サブエージェント自身が Claude の Read / Write / Edit で同じ要件を実行する。

```bash
CODEX_FAILED=
if command -v codex >/dev/null 2>&1; then
  codex exec $MODEL_FLAG --full-auto -C "$(pwd)" "$PROMPT" || CODEX_FAILED=1
else
  CODEX_FAILED=1
fi
# CODEX_FAILED=1 → codex への委譲を諦め、サブエージェント自身が Claude で実装/設計/テスト/レビューする
```

`command -v codex` は「未インストール」しか検出できない。「インストール済みだが未ログイン」は `codex exec` が実行時に失敗するため、`|| CODEX_FAILED=1` で受けてフォールバックする（auth エラー文言には依存しない）。フォールバックした場合は各エージェントのレポート「使用モデル」欄に `Claude フォールバック（Codex CLI 利用不可）` と明記する。

## 出力パス規約

Codex で生成するファイルの配置先は以下に従う。

| 出力物 | 配置先 |
|--------|--------|
| 実装プラン（todos.md） | `raw/issues/YYYY-MM-DD_<issue番号>/todos.md` |
| 設計ドキュメント（plan.md） | `raw/issues/YYYY-MM-DD_<issue番号>/plan.md` |

Issue に紐づく成果物はすべて `raw/issues/` 配下に配置し、プロジェクトルート直下には置かない。
Codex へのプロンプトでも出力先パスを明示的に指定すること。

## コーディングスタイルの方針

Codex への指示に Biome/ESLint/strict 等の個別ツール設定は含めない。
代わりに「既存コードベースのスタイル・パターンに従うこと」を指示する。
Codex は `.codex/instructions.md` を自動で読み込み、プロジェクト規約を把握する。

## Codex 駆動実装ワークフロー（実績パターン）

Issue の todos.md を入力に、Codex CLI で BE/FE を並行実装 → テスト → レビューを回す流れ。

### Phase 構成

| Phase | 内容 | Codex 並行度 | 備考 |
|-------|------|-------------|------|
| 1 | BE 実装 | `codex exec` x1 | domain → service → controller の順で指示 |
| 2 | FE 実装 | `codex exec` x1 | Phase 1 と **並行実行可** |
| 3 | テスト生成 | `codex exec` x2 | BE テスト + FE テストを並行 |
| 4 | レビュー + 修正 | Agent (sonnet) | Codex review-model は sandbox 制約あり、Agent の方が確実 |
| 5 | テスト実行・検証 | Bash | `./gradlew test` / `yarn test` |

### プロンプト設計のポイント

1. **変更ファイルを明示**: `## 変更1: path/to/file.kt` のようにファイル単位で指示
2. **既存コードパターンへの準拠を指示**: 「既存コードのスタイル・パターンに従うこと」
3. **処理順序を明示**: 判定フローの最終順序を箇条書きで指定
4. **既存の型/定数の再利用を指示**: 新規作成ではなく既存の enum/定数を使うよう明記

### Codex sandbox の制約

- `~/.gradle/` へのアクセスが拒否される → Gradle テスト実行は Codex 外で行う
- ネットワークアクセス不可 → 依存ダウンロードが必要なビルドは不可
- ESLint/Biome は Codex 内で実行不可 → PostToolUse hook に任せる

### 既存テストとの競合に注意

Codex で新チェックを追加すると、既存テストの期待値が変わることがある。
例: `.exe` を使っていた既存テストが `EXTENSION_NOT_ALLOWED` → `DANGEROUS_EXTENSION` に変わる。
→ Codex 実装後に必ず `./gradlew test` で既存テストの通過を確認する。
