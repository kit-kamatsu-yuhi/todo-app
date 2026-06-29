---
name: skillspector
description: NVIDIA SkillSpector で AI エージェント skill / ルールの安全性を scan する。Claude Code (`.claude/skills/`) だけでなく Cursor (`.cursor/rules/*.mdc`) / Cline (`.clinerules/`) / Windsurf (`.windsurfrules`) / Continue (`.continue/`) / Aider (`CONVENTIONS.md`) など任意のエージェント向け skill・ルール・プロンプトに対応。skill を導入する前、外部から skill を受け取ったとき、自作 skill のセキュリティを点検したいときに使う。「この skill 安全？」「skillspector で scan」「Cursor ルールをチェック」「Cline の skill 大丈夫？」「外部 skill を入れる前にチェック」「skill を監査して」「<URL> の skill 大丈夫？」「<repo> の prompt 安全？」で呼び出す。静的 scan（高速・無料・hook 自動）と LLM 評価（精密・Claude 経由）の 2 モード。exoloop を apm install した consumer に PostToolUse hook として自動配線される。
---

# skillspector — skill 安全性スキャナ

NVIDIA SkillSpector は AI エージェント skill のセキュリティスキャナ。Prompt injection、data exfiltration、privilege escalation、code execution、YARA 署名など **64 パターン / 16 カテゴリ** を検出する。`uvx` 経由でエフェメラル実行するので consumer 側の事前 install は不要（`uv` だけあればよい）。

## 配布形態

exoloop の `.apm/hooks/` primitive に同梱する。`apm install Clickan/exoloop` した consumer は：

- `.apm/hooks/claude-hooks.json` の PostToolUse エントリが consumer の `.claude/settings.json` に **自動 merge** される
- `setup-exoloop` skill が `apm_modules/Clickan/exoloop/.claude/hooks/scripts/scan-skill-on-write.sh` を consumer の `.claude/hooks/scripts/` にコピーする

結果として：

| トリガー | 動作 |
|---------|------|
| Claude Code から `.claude/skills/*/SKILL.md` 等を Write/Edit | hook が `uvx` で skillspector を呼び、`risk_score > 50` で exit 2 → Claude に findings 通知 |
| 上記以外のファイル編集 | hook は即 skip（数 ms） |

## 対応エージェント

スキャナ本体は **エージェント非依存**。hook は以下のパスで自動発火する。

| エージェント | hook 対象パス |
|------------|---------------|
| Claude Code | `**/.claude/skills/*/SKILL.md` |
| Cursor | `**/.cursor/rules/*.mdc`, `**/.cursorrules` |
| Cline | `**/.clinerules/*` |
| Windsurf | `**/.windsurfrules`, `**/.windsurf/rules/*` |
| Continue | `**/.continue/config.json`, `**/.continue/*.prompt` |
| Aider | `**/CONVENTIONS.md`, `**/.aider.conf.yml` |

手動 `skillspector scan <path>` は更に SKILL.md 単体・ディレクトリ・git URL・zip も受ける。

## 実行方式の自動選択

hook 内部のロジックは 3 段階フォールバック：

1. ターゲットから上方探索して `skillspector` を依存にもつ `pyproject.toml` が見つかれば、その uv プロジェクトを使う（cowork subtree など）
2. 見つからなければ `uvx --from git+https://github.com/NVIDIA/skillspector@<sha> skillspector scan ...` を実行
3. `uv` / `uvx` どちらも無ければ silent skip（consumer が後で導入する余地）

`uvx` は初回 ~10〜30 秒（依存 download）、2 回目以降は cache から数秒。

## 手動コマンド

```bash
# 静的 scan（hook と同じ挙動）
uvx --from git+https://github.com/NVIDIA/skillspector@1a7bf026a3cf0ecfd957b6c173244d51b3141baf \
    skillspector scan ./.claude/skills/some-skill/ --no-llm

# LLM 評価込み（Claude 経由）
export ANTHROPIC_API_KEY=sk-ant-...
export SKILLSPECTOR_PROVIDER=anthropic
uvx --from git+https://github.com/NVIDIA/skillspector@1a7bf026a3cf0ecfd957b6c173244d51b3141baf \
    skillspector scan ./.claude/skills/some-skill/

# 外部 URL を入れる前に scan
uvx --from git+https://github.com/NVIDIA/skillspector@1a7bf026a3cf0ecfd957b6c173244d51b3141baf \
    skillspector scan https://github.com/org/some-skill
```

## LLM 評価モード

skillspector は Anthropic Claude を provider に選べる。`SKILLSPECTOR_PROVIDER=anthropic` + `ANTHROPIC_API_KEY` を立てると、`claude-opus-4-6` がデフォルト、`meta_analyzer` は `claude-sonnet-4-6` で動く。

```bash
export ANTHROPIC_API_KEY=sk-ant-...   # 直接 export または .env で
export SKILLSPECTOR_PROVIDER=anthropic
# モデル上書きしたいときだけ
export SKILLSPECTOR_MODEL=claude-sonnet-4-6
```

`.env` を使うなら consumer プロジェクトの root に `ANTHROPIC_API_KEY` を書き、`direnv` / `dotenv` 等で session に流す（hook は env を継承する）。

## 終了コード

| code | 意味 | hook の反応 |
|------|------|-----|
| 0 | clean | 通す |
| 1 | `risk_score > 50` | exit 2 で Claude に findings 通知 |
| 2 | 引数エラー・実行不能 | wrapper が表面化 |

## 外部 skill 導入フロー（推奨）

ユーザーが「この skill を入れて」と URL/zip を渡してきたとき：

1. **scan を先に回す**（インストール前）
   ```bash
   uvx --from git+https://github.com/NVIDIA/skillspector@1a7bf026a3cf0ecfd957b6c173244d51b3141baf \
       skillspector scan <URL or path> --no-llm
   ```
2. 静的で findings が出たら **LLM 評価** に切り替えて再判定
3. risk_score が高い → ユーザーに findings を提示してインストール可否を判断してもらう
4. clean なら通常通り `apm install` / `git clone` / 手動コピーで取り込む
5. 取り込み後、`.claude/skills/` に置いた瞬間 PostToolUse hook が再走するので二重に防護される

## トラブルシュート

- **hook が動かない** → `cat ~/.claude/settings.json` で `scan-skill-on-write.sh` の登録を確認。無ければ `apm install Clickan/exoloop` を再実行し `/setup-exoloop` を回す
- **`uv: command not found`** → `brew install uv` または `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **初回起動が遅い** → uvx の依存 download が走る。`uvx --from ... skillspector --help` を 1 回叩いて温める
- **`--deep` で credit balance too low** → Anthropic コンソールで billing 設定。それでも進めたいなら `--no-llm` を使う
- **false positive がうるさい** → `--format sarif` で吐いて該当 rule id を確認し、skill 側で文言を修正

## 関連ファイル

| パス | 役割 |
|------|------|
| `exoloop/.apm/hooks/claude-hooks.json` | PostToolUse merge 定義 |
| `exoloop/.apm/hooks/scripts/scan-skill-on-write.sh` | uvx ベースの hook 本体 |
| `exoloop/.claude/hooks/scripts/scan-skill-on-write.sh` | mirror（setup-exoloop が consumer にコピー） |
| `exoloop/.claude/settings.json` | exoloop 自身の検証用 hook 登録 |

upstream: https://github.com/NVIDIA/skillspector
