---
name: e2e
description: |
  Markdown シナリオ駆動の E2E テスト自動化 skill。実行 backend として agent-browser CLI または chrome-devtools MCP を選択可能。
  TRIGGER when: 「E2E 実行」「E2E テストを動かして」「シナリオを回して」「example-login を試して」など、ブラウザ自動化による受入確認を依頼されたとき。
  DO NOT TRIGGER when: 単体テスト・統合テスト（→ test / testing skill）、Issue 起点の実装フロー（→ start-issue）、PR レビュー対応（→ address-pr-review）。
allowed-tools: Read, Write, Bash(agent-browser:*), Bash(npx:*), Bash(git:*), Bash(jq:*), Bash(mkdir:*), Bash(rm:*)
argument-hint: "[backend=agent-browser|chrome-devtools] [scenario=<name>]"
---

# E2E 自動化スキル

## 概要

Markdown で記述されたシナリオを LLM が解釈し、ブラウザを駆動して受入確認を行う。シナリオはバックエンド非依存の自然言語ステップとして書き、実行時に選択された backend へ翻訳される。

利用シーン:

- PR の動作確認をローカル / CI で機械的に回す
- 仕様変更時に既存シナリオを横断回帰させる
- 新規機能の受入条件を Markdown で固定し、実装後に同じシナリオで検証する

## 前提

- 実行 backend のいずれか 1 つ
  - `agent-browser` CLI（npm 経由でインストール、PATH に通っていること）
  - chrome-devtools MCP（Claude Code 側で MCP server が登録済みであること）
- `.env` / `.env.local` で `E2E_BASE_URL` 等のターゲット URL とテスト用 credential を設定する。`.env.example` をコピーして雛形を埋める

## 起動

2 通りの呼び出し形式がある。

```bash
# シェルから（CI もこの経路）
scripts/run-ai-e2e.sh                       # 全シナリオ
scripts/run-ai-e2e.sh example-login         # シナリオ名フィルタ

# Claude Code セッション内から
/e2e backend=agent-browser
/e2e backend=chrome-devtools scenario=example-login
```

`scripts/run-ai-e2e.sh` は内部で Claude Code を起動し、最終的に `/e2e backend=... scenario=...` 形式の prompt を流し込む。CI ではこちらを使う。

## バックエンド選択

デフォルト backend は `agent-browser`。chrome-devtools MCP は明示的にオプトインしたときのみ採用する。優先順位は上位が下位を上書きする。

1. skill 引数 `backend=agent-browser` または `backend=chrome-devtools`
2. 環境変数 `E2E_BACKEND`（値は `agent-browser` または `chrome-devtools`）
3. デフォルト `agent-browser`

CI で `agent-browser` を既定にする理由は、`state save` / `state load` の portable 性で login state を成果物として持ち回せること、および MCP server セットアップ非依存で再現できること。

セットアップ確認のヒント:

- agent-browser CLI: `npm i -g @anthropic-ai/agent-browser` で入れて `agent-browser --version`
- chrome-devtools MCP: Claude Code の MCP 設定に `chrome-devtools` を追加し、`/mcp` で接続を確認

## シナリオ書式

1 シナリオ = 1 ディレクトリ。`references/scenarios/<name>/scenario.md` の構造を取る。

```markdown
# <シナリオ名>

## 前提
- 必要な env / 事前状態

## ステップ
1. 自然言語の動作 1
2. 自然言語の動作 2
...

## Expectations
- 期待結果 1
- 期待結果 2
```

ステップは自然言語のみで書く。`@e1` のような snapshot ref や `click("#foo")` のような backend 固有 API 呼び出しを書かない。env 変数の差し込みは `${E2E_BASE_URL}` の形式で記述し、実行時に展開する。

シナリオを特定 backend にロックしたい場合は YAML frontmatter に `backend: agent-browser` または `backend: chrome-devtools` を入れる。指定が無ければ実行時の backend に従う。

## Backend capability matrix

chrome-devtools MCP のツール名は典型例で、利用中の MCP server の実装に合わせて読み替える。

| 動作 | agent-browser CLI | chrome-devtools MCP | 備考 |
|---|---|---|---|
| open（URL を開く） | `agent-browser open <url>` | `navigate_page` | 両方サポート |
| snapshot（DOM 取得） | `agent-browser snapshot` | `take_snapshot` | MCP は accessibility tree 形式 |
| click | `agent-browser click @e<n>` | `click`（snapshot ref 指定） | snapshot 形式が異なるため ref は再取得が必要 |
| fill（入力欄に値を入れる） | `agent-browser fill @e<n> <value>` | `fill` | 両方サポート |
| type（キー入力をエミュレート） | `agent-browser type @e<n> <text>` | `type` | agent-browser は ref 指定が必要 |
| select（セレクトボックス） | `agent-browser select @e<n> <value>` | `fill` で代用可 | MCP では select の専用 API が無い場合 fill で emulate |
| check（チェックボックス） | `agent-browser check @e<n>` | `click` で代用 | MCP では click による toggle で emulate |
| press（キー押下） | `agent-browser press <key>` | `press_key` | 両方サポート |
| scroll | `agent-browser scroll down <px>` | `scroll_page` | 両方サポート |
| get text | `agent-browser get text @e<n>` | snapshot から抽出 | MCP では snapshot 結果を読む |
| get url | `agent-browser get url` | `evaluate_script` で `location.href` | MCP は script 経由で取得 |
| get title | `agent-browser get title` | `evaluate_script` で `document.title` | MCP は script 経由で取得 |
| 要素出現待ち | `agent-browser wait @e<n>` | polling または retry loop | MCP は明示的 wait API が薄いため retry で emulate |
| URL 待ち | `agent-browser wait --url <pattern>` | retry loop | 同上 |
| networkidle 待ち | `agent-browser wait --load networkidle` | `wait_for` | MCP は DevTools 由来のため精度高 |
| 時間待ち | `agent-browser wait <ms>` | `wait_for` または sleep | 両方サポート |
| screenshot | `agent-browser screenshot [path]`（`--full` / `--output` 可） | `take_screenshot` | 両方サポート |
| pdf | `agent-browser pdf <path>` | `print_to_pdf` | MCP では emulate / unsupported |
| state 保存 | `agent-browser state save <path>` | unsupported | MCP では cookies / storage を script で抜くしかなく portable でない |
| state 復元 | `agent-browser state load <path>` | unsupported | 同上。CI で session 引き継ぎする場合は agent-browser 推奨 |
| 録画開始 | `agent-browser record start <path>` | `start_screen_recording` | MCP は DevTools recording を活用 |
| 録画停止 | `agent-browser record stop` | `stop_screen_recording` | 両方サポート |

「unsupported」は SHOULD NOT。emulate と書かれた項目は LLM が代替手順を組み立てる。MCP 列のツール名は典型例で、サーバ実装ごとに `chrome_navigate` / `cdp_navigate` などの命名差があるため `/mcp` で実ツール名を確認して読み替える。

### 翻訳例（自然言語ステップ → backend 呼び出し）

シナリオ `1. ${E2E_BASE_URL}/login を開く` の翻訳:

- agent-browser CLI

  ```bash
  agent-browser open "${E2E_BASE_URL}/login"
  agent-browser snapshot -i
  ```

- chrome-devtools MCP

  ```
  navigate_page(url="${E2E_BASE_URL}/login")
  take_snapshot()
  ```

両 backend とも、open 直後に snapshot を取って後続ステップで使う `@e<n>` ref を取得する。

## Step → command 翻訳ルール

LLM がシナリオステップを backend 呼び出しに変換するときの規約。

- 要素を触る前（click / fill / type / select / check / press 対象指定）に必ず snapshot を発行し、`@e<n>` ref を取得する。ref 無しで要素操作してはならない。
- 画面遷移（open / back / forward / reload / submit による navigate）または DOM mutation（モーダル開閉、SPA 内の route 切替、AJAX で要素追加）が起きた直後は、次の操作前に再度 snapshot を取る。古い ref は無効化されている前提で扱う。
- ある backend で取得した ref は別の backend に持ち込めない。backend を切り替えたら最初に snapshot を取り直す。
- 詳細は agent-browser 側の [`references/snapshot-refs.md`](../../../apm_modules/Clickan/dev-harness/.claude/skills/agent-browser/references/snapshot-refs.md) を参照（ref の寿命・スコープ・トラブルシュート）。

## 実行フロー

1. シナリオは引数で 1 件指定するか、未指定なら `references/scenarios/*.md` を全件実行する
2. backend を決定する（上記の優先順位）
3. 各シナリオを順に実行する。シナリオ内ステップは LLM が backend の capability matrix を参照して具体的なツール呼び出しに翻訳する
4. 終了時に JSON サマリーを標準出力する

JSON サマリーの推奨スキーマ:

```json
{
  "backend": "agent-browser",
  "totalScenarios": 3,
  "passed": 2,
  "failed": 1,
  "results": [
    { "name": "example-login", "status": "passed", "durationMs": 12500 }
  ]
}
```

実行結果は構造化サマリーとして出力するのが SHOULD。失敗時の screenshot / DOM snapshot は `_logs/` 配下に保存する。

## CI ガイド

- CI 既定 backend は `agent-browser`。`state save` / `state load` の portable 性により login state を成果物として持ち回せる
- chrome-devtools MCP はローカルデバッグ用途に推奨。Network パネル / Console / Performance といった DevTools 由来の情報が得られる
- CI では `.env.ci` を別途用意し、credential は CI Secret 経由でのみ注入する。`.env` / `.env.local` は配布物に含めない

## トラブルシューティング

- chrome-devtools MCP に接続できない: Claude Code 側で `/mcp` を実行し、`chrome-devtools` の status が ready か確認する。再起動で復旧することが多い。MCP サーバ側のログは Claude Code の MCP ログを参照
- agent-browser CLI が見つからない: `command -v agent-browser` で確認し、無ければ `npm i -g @anthropic-ai/agent-browser`。インストール後も見えない場合は PATH を確認する
- backend を切り替えた直後にシナリオが失敗する: snapshot ref（`@e<n>` 等）が backend ごとに異なるため、ステップに backend 固有 ref が混入していないか確認する。シナリオ Markdown は自然言語のみで書くのが原則
- env が読まれない: `.env` / `.env.local` / `.env.ci` の選択順を確認。CI 環境では `.env.ci` を優先し、ローカルでは `.env.local` を優先する
