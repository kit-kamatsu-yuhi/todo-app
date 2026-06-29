---
name: setup-exoloop
description: |
  APM 配布の後処理として settings.json / CLAUDE.md / AGENTS.md を merge し、APM が Claude target に deploy できない agents / rules / hooks を `apm_modules/` から `.claude/` にコピーする skill。
  TRIGGER when: 「AI駆動開発をセットアップ」「AI駆動開発を同期」「/setup-exoloop を実行」「settings を更新して」など、APM install 後のハーネス最終化を依頼されたとき。
  DO NOT TRIGGER when: 個別 skill の追加 (→ APM の `apm install`)、Issue 実装 (→ start-issue)、skill / agent の新規作成 (→ 直接編集)。
user_invocable: true
command: /setup-exoloop
argument-hint: "[--dry-run]"
---

# setup-exoloop

APM v0.8.11 は skills のみを Claude target (`.claude/skills/`) に deploy する。agents / rules / hooks は `apm_modules/` に download されるだけで `.claude/` には展開されない (2026-04-19 実機確認)。また `settings.json` / `CLAUDE.md` / `AGENTS.md` は APM の対象外。

本スキルはその 4 領域を担当する:

1. `settings.json` の key 単位 merge
2. `CLAUDE.md` の `## exoloop` セクション管理
3. `AGENTS.md` の `## exoloop` セクション管理
4. `apm_modules/<repo>/.claude/{agents,rules,hooks}/` を consumer の `.claude/` にコピー（APM が Claude target では届かない領域のブリッジ）

## 前提条件

1. APM CLI がインストール済み (`brew install microsoft/apm/apm` 等)
2. プロジェクトで `apm install Clickan/exoloop --target claude` が成功している
3. `apm_modules/Clickan/exoloop/` にベース repo の完全な clone が存在する（APM の download キャッシュ）

このスキル自体も APM 経由で `.claude/skills/setup-exoloop/SKILL.md` に deploy される。ベースパスは以下の 2 通りを順に試す:

1. `apm_modules/Clickan/exoloop/` (推奨・最新)
2. `apm_modules/_local/*` 配下のローカルパス dep (開発用)

いずれも無ければ「APM install を先に実行してください」と伝えて終了する。

## ワークフロー

### Step 0: base の解決

```bash
BASE_DIR=""
for candidate in apm_modules/Clickan/exoloop apm_modules/_local/*; do
  if [ -d "$candidate" ]; then
    BASE_DIR="$candidate"
    break
  fi
done
[ -z "$BASE_DIR" ] && echo "[x] apm_modules/ にベースが見つかりません。先に 'apm install Clickan/exoloop --target claude' を実行してください" && exit 1
```

### Step 1: settings.json のマージ

プロジェクトの `.claude/settings.json` と `$BASE_DIR/.claude/settings.json` を key 単位で merge する。

#### `hooks`（配列マージ）

イベントタイプごと（`PreToolUse`, `PostToolUse`, `Stop`, `SessionStart`）に:

1. プロジェクト側のフック定義を保持する
2. ベース側のフック定義を追加する
3. 同じ `command` 値を持つフックは重複追加しない
4. 同じ `matcher` を持つエントリは `hooks` 配列をマージする

#### `env`（キー単位マージ）

- プロジェクト側のキーを優先する（上書きしない）
- ベースにしか存在しないキーを追加する
- **注意**: `ANTHROPIC_VERTEX_PROJECT_ID` などプロジェクト固有の値は絶対に上書きしない

#### `enabledPlugins`（キー単位マージ）

- プロジェクト側のキーを優先する
- ベースにしか存在しないキーを追加する

#### settings.json が存在しない場合

ベースの settings.json をそのままコピーする。ただし `env` の値はプロジェクトに合わせて変更が必要な旨を警告する。

### Step 2: CLAUDE.md の `## exoloop` セクション管理

プロジェクトの `CLAUDE.md` に `## exoloop` セクションを追加・更新する。**APM compile は既存 CLAUDE.md を無警告で全上書きするため、本スキルのローカルマージを採用する**。

#### CLAUDE.md が存在しない場合

`CLAUDE.md` を新規作成し、`## exoloop` セクションのみを記載する。

#### CLAUDE.md が存在する場合

- 既に `## exoloop` セクションがあれば、**そのセクションのみ**最新のベースで上書きする
- 無ければ、ファイル末尾に追記する
- **セクション外の内容は絶対に触らない**

#### セクションの内容

`$BASE_DIR/CLAUDE.md` を読み取り、以下の構成で `## exoloop` セクションを生成する:

```markdown
## exoloop

### 実行フロー（必須）

GitHub Issue URL（`https://github.com/.../issues/\d+`）を受け取って開発を開始する場合、以下のフローに**必ず**従うこと:

1. `/start-issue` コマンドを Skill ツールで実行する
2. Phase A: `/plan-issue` で計画策定 → plan.md + todos.md → ユーザー承認
3. Phase B: `/codex-team all` で実装/テスト/レビュー
4. Phase C: `/create-pr` で PR 作成（plan.md, todos.md, changes.md の3ファイル必須）
5. レビュー対応は `/address-pr-review` → `/codex-team review`

### Sub-Agents 起動ガイド（必須）

| タイミング | 起動するエージェント | 起動方法 |
|-----------|--------------------|---------|
| 設計フェーズ | codex-design | Agent ツールで起動 |
| テスト作成 | codex-test | Agent ツールで起動 |
| 実装 | codex-implement | Agent ツールで起動 |
| レビュー | codex-review, review-agent | Agent ツールで並列起動 |
| 受入基準判定 | acceptance-criteria-agent | Agent ツールで起動 |
| レビュー対応 | codex-implement, codex-test, codex-review, review-agent | Claude（指揮官）がオーケストレーション |

※ review-agent は wiki/pages/reviews/, raw/ の過去レビュー内容を参照する
※ Codex CLI 未インストール時は Claude 単体で代替する（codex-* エージェントのフォールバック）

### Rules / Skills / Sub-Agents / Docs / Hooks

（ベース CLAUDE.md の該当セクションの内容をそのまま転記し、見出しレベルを `##` → `###` に下げる）
```

転記対象は「プロジェクト概要」「技術スタック」を除く。見出しレベルを 1 つ下げて本セクション内に収める。

### Step 3: AGENTS.md の `## exoloop` セクション管理

プロジェクトに `AGENTS.md` が存在する、または Copilot / Codex / Cursor を併用する場合のみ実施。処理は CLAUDE.md と同一（`## exoloop` セクションの append or overwrite）。本セクション外は絶対に触らない。`apm compile --target copilot` は使わない（AGENTS.md 全体を上書きするため）。

### Step 3b: agents / rules / hooks の不足分コピー（APM ブリッジ）

APM v0.8.11 は claude target で `.claude/agents/`, `.claude/rules/` に deploy しない。
APM v0.11+ の hooks primitive (`.apm/hooks/claude-hooks.json`) は `.claude/settings.json` の
hooks フィールド merge までは動くが、script 本体を consumer の `.claude/hooks/scripts/` に
deploy しないため、command path (`.claude/hooks/scripts/<name>.sh`) の resolve に失敗する。

本スキルがこれら 3 領域を `apm_modules/` から補填する。**プロジェクト側に既に存在する
同名ファイル・ディレクトリは上書きしない**（プロジェクト固有の差分を尊重）。

対象（いずれも base repo 側の対応物を source とする）:

| source | destination | 単位 |
|---|---|---|
| `$BASE_DIR/.claude/agents/*/` | `.claude/agents/` | ディレクトリ単位 |
| `$BASE_DIR/.claude/rules/*` | `.claude/rules/` | ファイル単位（`languages/` サブディレクトリ含めて再帰） |
| `$BASE_DIR/.claude/hooks/scripts/*.sh` | `.claude/hooks/scripts/` | ファイル単位（`chmod +x` 保持） |

除外（source にあっても copy しない）:
- ベースプロジェクト固有の skill: `indie-app-idea`, `influencer-marketing`, `instagram-marketing`, `manim`, `tiktok-*` 系, `x-marketing`, `svg-to-image`, `agent-browser`, `entire`, `xai-api`
- 特化 agent: `grok-search`, `manim-review-agent`
- hooks: `check-entire-installed.sh`, `run-entire.sh` (entire 固有、`claude-hooks.json` の merge 対象からも除外済み)

※ `aws-infra-review-agent`, `gcp-infra-review-agent` は配布対象に含める（インフラレビュー用途で一般的に有用）。
※ hooks の `.claude/settings.json` への merge は APM v0.11+ primitive (`.apm/hooks/claude-hooks.json`) が自動で行うため本 step では扱わない。本 step は script 本体のコピーのみ担当する（Issue #222 / PR #305 install test で必要性を再確認）。

### Step 3c: lefthook + gitleaks の config と script を配布

consumer プロジェクトで `git commit` 時に secret 流出を止めるため、以下を配布する:

| source | destination | 処理 |
|---|---|---|
| `$BASE_DIR/lefthook.template.yml` の `pre-commit.commands.gitleaks` 節 | consumer の `lefthook.yml` | キー単位マージ（既存 `gitleaks` キーがあれば consumer 側を尊重） |
| `$BASE_DIR/scripts/hooks/gitleaks-protect.sh` | consumer の `scripts/hooks/gitleaks-protect.sh` | ファイルコピー + `chmod +x`（既存があれば上書きしない） |

処理の詳細:

1. consumer に `lefthook.yml` が無ければ `exoloop/lefthook.template.yml` をそのままコピーする
2. 既存 `lefthook.yml` がある場合、`pre-commit.commands.gitleaks` が未定義ならキーを追加する。**`pre-commit` 以外のキー (`pre-push` 等) には触らない**
3. `scripts/hooks/gitleaks-protect.sh` をコピーし、`GITLEAKS_ENABLE=0` と「未インストール WARN」のフォールバック挙動を持たせる
4. `.gitleaks.toml` は consumer 固有の allowlist が必要なため**自動配置しない**。skill 出力で「`exoloop/.claude/skills/gitleaks/SKILL.md` の最小 config 節を参考に `.gitleaks.toml` を作成してください」と案内する

consumer がすでに別ルートで gitleaks hook を持っている場合（pre-commit framework 等）はマージをスキップし、重複設定にならないよう警告のみ出す。

### Step 3d: lefthook / gitleaks CLI のインストールと git hook 配線

config と script を置いただけでは `.git/hooks/pre-commit` が呼ばれず secret 検査が動かない。本 step で CLI を自動インストールし、`lefthook install` で git hook へ配線する。

#### 3d-1. lefthook CLI のインストール

1. `command -v lefthook` で存在確認する。あれば skip。
2. 無ければ OS を判定して以下のコマンドを実行する。consumer に確認プロンプトを出した上で実行する（**サイレントに `brew install` を走らせない**。失敗時のリカバリを利用者が把握できる粒度に保つ）:

   | プラットフォーム | コマンド |
   |---|---|
   | macOS / Linux + Homebrew | `brew install lefthook` |
   | Linux (npm 可) | `npm install -g lefthook` または `npx --yes lefthook ...` |
   | Windows | `winget install evilmartians.lefthook` または `scoop install lefthook` |
   | フォールバック | https://github.com/evilmartians/lefthook/releases から release binary を配置 |

3. 自動 install を選ばなかった/失敗した場合は WARN を出し、`lefthook install` の実行を skip する（設定ファイルは置いた状態で終わる）。

#### 3d-2. gitleaks CLI のインストール

1. `command -v gitleaks` で存在確認する。あれば skip。
2. 無ければ以下を提示・実行する:

   | プラットフォーム | コマンド |
   |---|---|
   | macOS / Linux + Homebrew | `brew install gitleaks` |
   | Linux (apt) | `apt-get install -y gitleaks`（gitleaks v8 系がパッケージにない場合は release binary 推奨） |
   | フォールバック | https://github.com/gitleaks/gitleaks/releases から release binary を配置 |

3. consumer の `scripts/hooks/gitleaks-protect.sh` は CLI 未検出時に `GITLEAKS_ENABLE=0` 相当の warning を出して **pre-commit を通す**（commit が止まらない退避路）。本 step で CLI 配置が出来た場合のみ、配線後の動作確認として `gitleaks version` を出力する。

#### 3d-3. `lefthook install` で git hook を配線

1. consumer リポジトリのルートで `lefthook install` を実行する。
2. これにより `.git/hooks/pre-commit` などの shim が生成され、`lefthook.yml` の commands が `git commit` 時に呼ばれるようになる。
3. **`.git/` が無い consumer**（git init 前）では `lefthook install` が失敗する。skill は warning を出し、後から `lefthook install` を実行するよう案内する。
4. `.git/hooks/pre-commit` が既に他ツール（pre-commit framework, husky 等）の shim になっている場合は上書きしない。consumer に手動でのマージを依頼する旨を出力する。

#### 3d-4. 動作確認

`lefthook install` 成功後、`lefthook run pre-commit --files .gitleaks.toml` などを推奨実行として案内する。失敗してもこの step は致命的ではない（commit 時に再評価される）。

### Step 4: self-update

APM install で `.claude/skills/setup-exoloop/SKILL.md` 自体はすでに最新版に deploy 済みのため、本スキル側で自己更新ロジックは持たない。APM の lockfile (`apm.lock.yaml`) の `resolved_commit` で追跡する。

### Step 5: 実行結果サマリー

```markdown
## セットアップ結果

### base
- 検出パス: apm_modules/Clickan/exoloop/ (or apm_modules/_local/<name>/)
- resolved_commit: <apm.lock.yaml の記録>

### settings.json マージ結果
- hooks: PreToolUse に N 件追加, PostToolUse に N 件追加
- env: N 件追加（既存キーは保持）
- enabledPlugins: 変更なし or 追加

### CLAUDE.md
- `## exoloop` セクション: 新規作成 / 上書き / 変更なし

### AGENTS.md
- `## exoloop` セクション: 新規作成 / 上書き / 変更なし / 非対象

### lefthook + gitleaks
- lefthook.yml: pre-commit.gitleaks を追加 / 既存維持
- scripts/hooks/gitleaks-protect.sh: 配布 / 既存維持
- lefthook CLI: インストール済み / 自動 install 実行 / skip（理由）
- gitleaks CLI: インストール済み / 自動 install 実行 / skip（理由）
- `lefthook install`: 実行 / skip（.git 未検出 等の理由）

### 注意事項
- settings.json の env 値（ANTHROPIC_VERTEX_PROJECT_ID 等）はプロジェクトに合わせて変更してください
- CLAUDE.md のセクション外の内容には触れていません
- `.gitleaks.toml` は自動配置しません。exoloop/.claude/skills/gitleaks/SKILL.md を参考に作成してください
```

## 既存の skill / agent / rule / hook 配布について

本スキルはそれらの配布を担当しない。配布は APM の責務:

```bash
# 例: Clickan/exoloop の skill / agent / rule / hook を最新化
apm install Clickan/exoloop --target claude
```

ただし現時点で `.apm/` への移行が完了しているのは一部の skill のみ。未移行の asset は APM では届かない。`wiki/pages/infrastructure/apm-harness.md` の Phase 2 計画を参照し、順次 `.apm/` に移行する。

## Dev-Harness からの移行

旧 `Clickan/dev-harness` を install 済みの consumer は、本 SKILL を呼ぶ前に `exoloop/scripts/migrate-from-dev-harness.sh` を実行する。

```bash
# apm_modules 経由（exoloop install 後）
bash apm_modules/Clickan/exoloop/scripts/migrate-from-dev-harness.sh --version vX.Y.Z

# まだ install 前なら一時 clone でも OK
git clone --depth 1 git@github.com:Clickan/exoloop.git /tmp/exoloop \
  && bash /tmp/exoloop/scripts/migrate-from-dev-harness.sh --version vX.Y.Z
```

スクリプトが apm.yml の `Clickan/dev-harness` → `Clickan/exoloop#vX.Y.Z` 書換、apm_modules 旧 clone 削除、`setup-dev-harness` skill 削除、`apm install` まで一括で行う。終わったら本 `/setup-exoloop` を実行して残りの整備を行う。`--version` には必ず exoloop 名で公開された tag（v1.13.0 以降）を指定すること（旧 dev-harness tag は内部の name フィールドと `setup-dev-harness` skill 名が旧名のままなため）。
