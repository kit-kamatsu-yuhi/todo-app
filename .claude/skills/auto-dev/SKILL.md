---
name: auto-dev
description: auto-dev devcontainer の起動・運用・トラブルシューティング。label:auto-dev の Issue を自動処理する開発環境の知識を提供する。`/setup-auto-dev` で新規リポジトリにセットアップする。
---

# auto-dev Skill

GitHub Issue を自動で処理する devcontainer ベースの開発環境。`label:auto-dev` が付いた Issue をポーリングし、Claude CLI でプラン作成・実装・PR作成・マージまでを自動実行する。

## `/setup-auto-dev` — 新規リポジトリへのセットアップ

新しいリポジトリで auto-dev を動かすためのファイルを生成する。リポジトリのコードを読み取り、プロジェクトに合った Dockerfile を動的に生成する。

### 実行手順

#### Step 1: プロジェクトスタック検出

リポジトリのルートにあるファイルを読み取り、使用言語・ツールを判定する。

| 検出ファイル | スタック | ランタイム |
|-------------|---------|-----------|
| `package.json` | Node.js | node |
| `pnpm-lock.yaml` | Node.js (pnpm) | node |
| `yarn.lock` | Node.js (yarn) | node |
| `bun.lockb` / `bun.lock` | Node.js (bun) | node |
| `pyproject.toml` / `requirements.txt` | Python | python3 |
| `go.mod` | Go | golang |
| `Cargo.toml` | Rust | rust |
| `build.gradle.kts` / `build.gradle` | Kotlin/Java (Gradle) | jvm |
| `pom.xml` | Java (Maven) | jvm |
| `Gemfile` | Ruby | ruby |
| `mix.exs` | Elixir | elixir |

複数のスタックが混在する場合はすべて含める。

#### Step 2: Dockerfile 生成

`.devcontainer/auto-dev/Dockerfile` を生成する。以下のルールに従う。

**ベースイメージ選択:**

Claude CLI は npm でインストールするため、Node.js は常に必要。

| プライマリスタック | ベースイメージ |
|-------------------|---------------|
| Node.js のみ | `node:22-slim` |
| Python のみ / Python + Node.js | `node:22-slim`（python3 を apt で追加） |
| Go のみ / Go + Node.js | `node:22-slim`（golang を apt で追加、または公式バイナリ） |
| JVM のみ / JVM + Node.js | `node:22-slim`（openjdk を apt で追加） |
| Rust のみ / Rust + Node.js | `node:22-slim`（rustup を追加） |
| その他 | `node:22-slim`（必要なランタイムを apt で追加） |

**Dockerfile 構成（この順序で記述する）:**

```dockerfile
FROM node:22-slim

# 1. System dependencies（常に含める）
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl jq ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. プロジェクト固有のランタイム（検出結果に応じて追加）
#    - Python: python3 python3-pip python3-venv + uv (curl でインストール)
#    - Go: golang (apt) または公式バイナリ
#    - JVM: default-jdk
#    - Rust: rustup (curl でインストール)
#    - Ruby: ruby ruby-dev
#    - ビルドツール (C拡張が必要な場合): make g++

# 3. gh CLI（常に含める）
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# 4. パッケージマネージャー（検出結果に応じて）
#    - pnpm-lock.yaml → npm install -g pnpm
#    - yarn.lock → node:22-slim には yarn がプリインストール済み。バージョンを変えたい場合のみ npm install -g yarn@x.x.x
#    - Gemfile → gem install bundler

# 5. リンター/フォーマッター（検出結果に応じて）
#    - Node.js: npm install -g @biomejs/biome（biome.json があれば）
#    - Python: pip install ruff（pyproject.toml に ruff があれば）

# 6. Claude CLI + Codex CLI（常に含める）
RUN npm install -g @anthropic-ai/claude-code@2.1.159 @openai/codex@0.135.0

# 7. Non-root user（常に含める）
RUN useradd -m -s /bin/bash autodev

# 8. ディレクトリ + npm global prefix（常に含める）
RUN mkdir -p /var/auto-dev/state /var/auto-dev/logs /var/auto-dev/metrics \
        /workspace /home/autodev/.npm-global \
    && chown -R autodev:autodev /var/auto-dev /workspace /home/autodev/.npm-global

ENV NPM_CONFIG_PREFIX=/home/autodev/.npm-global
ENV PATH="/home/autodev/.npm-global/bin:${PATH}"
ENV COREPACK_ENABLE_AUTO_PIN=0
ENV COREPACK_ENABLE_STRICT=0

WORKDIR /workspace

# 9. スクリプトコピー（常に含める）
COPY entrypoint.sh /usr/local/bin/auto-dev-entrypoint.sh
COPY lib/ /usr/local/lib/auto-dev/
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/auto-dev-entrypoint.sh /usr/local/lib/auto-dev/*.sh /usr/local/bin/auto-dev-status

COPY init-user.sh /usr/local/bin/init-user.sh
RUN chmod +x /usr/local/bin/init-user.sh

ENTRYPOINT ["/usr/local/bin/init-user.sh"]
```

**Dockerfile 生成時の判断基準:**

- `package.json` の `dependencies` / `devDependencies` を読み、ネイティブモジュール（`sharp`, `bcrypt`, `sqlite3` 等）があれば `make g++ python3` をシステム依存に追加する
- `Dockerfile` や `docker-compose.yml` が既にあれば、そこからヒントを得る（使用ポート、必要なサービス等）
- `.node-version` / `.nvmrc` / `.python-version` / `go.mod` の go directive からバージョンを読み取り、ベースイメージのバージョンを合わせる
- `.tool-versions`（asdf）があればそこからもバージョン情報を取得する

#### Step 3: devcontainer スクリプトのコピー

`.claude/skills/auto-dev/devcontainer/` 内のスクリプトを `.devcontainer/auto-dev/` にコピーする。

```
.claude/skills/auto-dev/devcontainer/entrypoint.sh    → .devcontainer/auto-dev/entrypoint.sh
.claude/skills/auto-dev/devcontainer/init-user.sh      → .devcontainer/auto-dev/init-user.sh
.claude/skills/auto-dev/devcontainer/lib/*.sh          → .devcontainer/auto-dev/lib/*.sh
```

既に `.devcontainer/auto-dev/` にファイルが存在する場合は上書きするか確認する。

#### Step 4: docker-compose.auto-dev.yml 生成

`.claude/skills/auto-dev/templates/docker-compose.auto-dev.yml` をプロジェクトルートにコピーし、`{{REPO_NAME}}` をリポジトリ名に置換する。

リポジトリ名の取得:
```bash
# origin URL から repo 名のみを抽出（owner を除く）
git remote get-url origin | sed -E 's|.*[:/]([^/]+/)?([^/.]+)(\.git)?$|\2|'
```

`container_name` は `auto-dev-<リポジトリ名>` となる（例: `auto-dev-ai-driven-development`）。同じホストで複数プロジェクトのコンテナを同時に立ち上げるため、リポジトリ名で一意にする。

#### Step 5: .env.example 生成

`.claude/skills/auto-dev/templates/env.example` をプロジェクトルートに `.env.example` としてコピーする。

`AUTO_DEV_REPO` の値をリポジトリの `origin` URL から自動設定する:

```bash
# origin URL から owner/repo を抽出
git remote get-url origin | sed -E 's|.*[:/]([^/]+/[^/.]+)(\.git)?$|\1|'
```

#### Step 6: .gitignore 更新

`.gitignore` に以下を追加する（既に含まれていればスキップ）:

```
# auto-dev
.env.agent
```

#### Step 7: 結果サマリー

```
## auto-dev セットアップ完了

### 生成ファイル
- .devcontainer/auto-dev/Dockerfile（<検出スタック> 向け）
- .devcontainer/auto-dev/entrypoint.sh
- .devcontainer/auto-dev/init-user.sh
- .devcontainer/auto-dev/lib/*.sh
- docker-compose.auto-dev.yml
- .env.example

### 更新ファイル
- .gitignore（.env.agent を追加）

### 次のステップ
1. cp .env.example .env.agent
2. .env.agent を編集（GITHUB_TOKEN, AUTO_DEV_REPO を設定）
3. docker compose -f docker-compose.auto-dev.yml up -d --build
4. docker exec -it -u autodev auto-dev-<リポジトリ名> claude
   # REPL で /login を入力（v2.1.114 以降は subcommand 廃止）
```

---

## Docker セットアップ（WSL2 / Linux）

Docker が未インストールの場合、以下を実行する。

```bash
# 公式 GPG キーとリポジトリ追加
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Docker インストール
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 現在のユーザーを docker グループに追加（sudo 不要にする）
sudo usermod -aG docker $USER
newgrp docker

# Docker 起動・確認
sudo service docker start
docker run hello-world
```

> **WSL2 の注意**: WSL2 で運用する場合は「WSL2 環境の必須設定」セクションを必ず実施する。VM の idle timeout 対策をしないとターミナルを閉じた際にコンテナが停止する。

## 起動手順

```bash
# 1. ビルド & 起動
docker compose -f docker-compose.auto-dev.yml up -d --build

# 2. Claude CLI ログイン（初回のみ）
docker exec -it -u autodev auto-dev-<リポジトリ名> claude
   # REPL で /login を入力（v2.1.114 以降は subcommand 廃止）

# 3. ログ確認
docker exec -it -u autodev auto-dev-<リポジトリ名> tail -f /var/auto-dev/logs/*.log
```

## 停止

```bash
docker compose -f docker-compose.auto-dev.yml down
```

## 環境変数（.env.agent）

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `AUTO_DEV_REPO` | 対象リポジトリ | — |
| `AUTO_DEV_POLL_INTERVAL` | ポーリング間隔（秒） | `300` |
| `AUTO_DEV_ISSUE_LABEL` | 処理対象ラベル | `auto-dev` |
| `AUTO_DEV_MAX_TURNS` | Claude CLI 最大ターン数 | `200` |
| `AUTO_DEV_MAX_BUDGET_USD` | 1Issue あたり予算上限 | `5.00` |
| `AUTO_DEV_DAILY_BUDGET_USD` | 1日あたり予算上限 | `50.00` |
| `AUTO_DEV_WORKER_TIMEOUT` | Worker タイムアウト（秒） | `1800` |
| `AUTO_DEV_LOG_RETENTION_DAYS` | ログ保持日数 | `1` |
| `GITHUB_TOKEN` | GitHub PAT | — |

## 動作フロー

Issue のコメント履歴を上から読み、フェーズを自動判定する。

```
plan → wait-plan → replan(ループ) → implement → wait-review → revise-pr(ループ) → merge → done
```

1. `label:auto-dev` の Issue を検出
2. コメントから現在のフェーズを導出（`derive_phase`）
3. フェーズに応じたアクションを実行

| フェーズ | 条件 | アクション |
|---------|------|-----------|
| `plan` | 実装計画が未投稿 | `/plan-issue` で計画を Issue にコメント |
| `wait-plan` | 計画投稿済み、ユーザー応答なし | 待機 |
| `replan` | ユーザーがフィードバック（承認以外） | フィードバック反映して計画更新 |
| `implement` | ユーザーが承認（OK/Yes/進めろ等） | `/codex-team all` で実装 → `/create-pr` で PR 作成 |
| `wait-review` | PR 作成済み、ユーザー応答なし | 待機 |
| `revise-pr` | ユーザーが PR にフィードバック | `/address-pr-review` → `/codex-team review` で修正 |
| `merge` | ユーザーが PR を承認 | squash merge |
| `done` | マージ完了 | スキップ |

## フェーズ別の実行フロー

### plan フェーズ

Skill ツールで `/plan-issue` を呼び出し、実装計画を策定する。

- Issue の要件分析 → UML → API → DB → テスト → タスク分解 → リスク分析
- 参照スキル: `plan-issue`, `uml`, `api-design`, `db-design`, `security`, `testing`
- plan.md + todos.md を生成し、Issue にコメントとして投稿する

### implement フェーズ

`/start-issue` の Phase B → Phase C に対応する。

1. Skill ツールで `/codex-team all` を呼び出す
   - codex-implement + codex-test を Agent ツールで並列起動
   - acceptance-criteria-agent で受入基準の RED/GREEN 判定
   - codex-review + review-agent を Agent ツールで並列起動
   - 受入基準が全 GREEN になるまで最大5回ループ
2. Skill ツールで `/create-pr` を呼び出して PR を作成する

### revise-pr フェーズ

1. Skill ツールで `/address-pr-review` を呼び出してレビューコメントを取得・分析する
2. Skill ツールで `/codex-team review` を呼び出して修正を実行する

### plan-product との関係

Issue が「新プロダクト企画」レベルの大きなスコープの場合は `plan-product` の手法（ニーズ検証 → 要件定義 → Issue 分割）を適用する。通常の機能追加・バグ修正は `plan-issue` で十分。

## 承認キーワード

以下のいずれかがコメントに含まれると承認と判定:

`OK`, `Yes`, `LGTM`, `進めろ`, `進めて`, `実装して`, `approve`, `マージして`, `merge`

## アーキテクチャ

```
docker-compose.auto-dev.yml
├── .devcontainer/auto-dev/
│   ├── Dockerfile           # プロジェクト固有（/setup-auto-dev で生成）
│   ├── init-user.sh         # root→autodev 権限修正
│   ├── entrypoint.sh        # ポーリングループ
│   └── lib/
│       ├── process-issue.sh # フェーズ導出 + アクション実行
│       ├── state.sh         # ロック管理
│       ├── notify.sh        # GitHub コメント投稿
│       ├── init-project.sh  # プロジェクト初期化（自動検出）
│       └── validate-env.sh  # 環境変数バリデーション
├── .env.agent               # 環境変数（.gitignore 対象）
└── .env.example             # 環境変数テンプレート
```

## WSL2 環境で 24/7 稼働させる

Windows 環境で auto-dev を常駐運用する場合、**Docker Desktop + WSL Integration** を主軸にする。詳細設計は [`wiki/pages/infrastructure/auto-dev-stability.md`](../../../../wiki/pages/infrastructure/auto-dev-stability.md) を参照。

### 前提

Docker Desktop の `docker-desktop` distro が WSL2 上で常時 pin されるため、ユーザー distro（Ubuntu）が idle shutdown してもコンテナは生存する。tmux 常駐運用は**不要**（廃止）。

### セットアップ手順

1. **Docker Desktop を自動起動化する**
   - Settings → General → **Start Docker Desktop when you sign in** をオン
2. **WSL Integration を有効化する**
   - Settings → Resources → **WSL Integration → Ubuntu on**
3. **`.wslconfig` で distro idle を無効化する**
   - `%USERPROFILE%\.wslconfig` に書く:
     ```ini
     [wsl2]
     vmIdleTimeout=-1
     swap=2GB
     # memory は最初は書かない（host RAM 50% デフォルト）。
     # Vmmem が 70%+ を常時食うのを 1 週間観察したら cap を入れる。
     ```
4. **PowerShell で `wsl --shutdown`** を実行して設定を反映する
5. **Windows 電源プラン「スリープしない」**（任意。バッテリー機で有用）

### なぜ安定するか

- コンテナは `docker-desktop` distro で走る。Ubuntu が idle でも巻き込まれない
- `restart: unless-stopped` + `logging.options.max-size=10m` で crash 時の復帰と log 肥大化を同時に抑える
- コンテナ内の `heartbeat` が 30s ごとに `/var/auto-dev/state/heartbeat` を更新する。WSL idle 抑止 + 観測性
- SSH 切断後も Docker 常駐で影響なし。tmux セッション維持は不要

### 監視コマンド

```bash
# コンテナ稼働
docker inspect -f '{{.State.Status}}' auto-dev-<repo>

# Heartbeat 最終更新
docker exec auto-dev-<repo> cat /var/auto-dev/state/heartbeat

# phase 分布 + 直近エラー + heartbeat
docker exec auto-dev-<repo> auto-dev-status

# 構造化ログ抽出
docker exec auto-dev-<repo> jq 'select(.level=="error")' /var/auto-dev/logs/*.jsonl | tail
```

Windows 側（PowerShell）:

```powershell
wsl -l -v                                 # distro 稼働確認
docker ps --filter name=auto-dev-         # コンテナ一覧
```

### プロジェクト配置

WSL2 ファイルシステム上（`~/` 配下）に配置する。`/mnt/c/` は I/O が遅く、ボリューム権限の問題も起きやすい。

### 動作確認

1. `docker compose -f docker-compose.auto-dev.yml up -d --build`
2. `docker inspect -f '{{.State.Status}}' auto-dev-<repo>` が `running` になる
3. `docker exec auto-dev-<repo> cat /var/auto-dev/state/heartbeat` が 30s 以内に更新される
4. WSL ターミナルを全て閉じて 5分以上待つ
5. Windows を開き直して `docker ps` で コンテナが `Up X minutes` であれば成功
6. PowerShell で `wsl --terminate Ubuntu` を実行しても `docker ps` でコンテナ生存継続

### Windows 再起動後に動かない場合

Docker Desktop の自動起動設定を確認する。必要なら Task Scheduler に「At log on」で `"C:\Program Files\Docker\Docker\Docker Desktop.exe"` を登録する。

### 後回し項目（YAGNI）

観測で問題が出たら追加する。初期構成には含めない。

| 項目 | 入れる判断基準 |
|---|---|
| `memory=<N>GB` | Vmmem が host RAM 70%+ を常時食う状態を 1 週間観察したら |
| healthcheck | コンテナ生きてるのに処理止まってた、を 1 回でも観測したら |
| `networkingMode=mirrored` | localhost 問題が出たら |

## Linux / macOS での常駐

Linux サーバー: `sudo systemctl enable docker` のみ。suspend 無効化は必要に応じて `systemctl mask sleep.target` 系。

macOS: Docker Desktop 自動起動をオン。バッテリー機なら System Settings → Battery / Energy で「Prevent automatic sleeping」または `caffeinate -di` LaunchAgent を常駐させる。

## 初回セットアップ: Claude ログイン

**default は subscription OAuth ログイン**（Anthropic Max / ChatGPT 経由）。
auto-dev は API key 不要・定額・キャッシュ有効で運用する設計。

ANTHROPIC_API_KEY を `.env.agent` に設定すれば key 認証も可能だが、subscription を
持っているならそちらを優先する（コスト予測が立てやすい、長時間稼働でも青天井にならない）。

### 手順

1. コンテナを通常通り起動する

   ```bash
   docker compose -f docker-compose.auto-dev.yml up -d --build
   ```

2. 別ターミナルからコンテナに入り、Claude REPL で `/login` を実行する

   ```bash
   docker exec -it -u autodev auto-dev-<リポジトリ名> claude
   # REPL で /login を入力（v2.1.114 以降は subcommand 廃止）
   ```

   `docker exec -it` が自動的にPTYを割り当てるため、コンテナ側の `tty` 設定は不要。

3. ログイン完了後、entrypoint が自動検知してポーリングを開始する

## 初回セットアップ: Codex ログイン（/codex-team を使う場合のみ）

`/codex-team` skill が `codex exec` を呼ぶため、codex CLI も login しておく。

**default は subscription OAuth ログイン**（ChatGPT 経由）。利用可能なモデルは認証方式
（subscription / API key）に依存する。モデルは codex CLI の default（最新）が使われる。

OPENAI_API_KEY を `.env.agent` に設定すれば key 認証も可能だが、subscription を持って
いるならそちらを優先する（コスト予測 / レート制限 / 利用可能モデルの観点）。

### 手順

1. コンテナを通常通り起動する（claude login と同じ docker compose 起動）

2. 別ターミナルからコンテナに入り、`codex login` を実行する

   ```bash
   docker exec -it -u autodev auto-dev-<リポジトリ名> codex login
   # 表示される URL を host のブラウザで開いて OAuth 認証
   ```

3. completion 後、`codex exec --version` などで動作確認

   ```bash
   docker exec -u autodev auto-dev-<リポジトリ名> codex exec --version
   ```

### モデル指定（任意）

モデルは codex CLI の default（最新）が使われる。固定したい場合のみ
`.codex.local.toml` をプロジェクトルートに配置する（任意）：

```toml
# 指定するとそのモデルに固定される。未指定なら codex CLI の default(最新)。
model = "<固定したいモデル名>"
```

`CODEX_MODEL` env でも override 可能。

### なぜ docker-compose に tty: true を設定しないのか

コンテナのメインプロセスに PTY を割り当てると、claude CLI の大量出力（JSON）が
PTY バッファ（約4KB）を満杯にし、write がブロックしてプロセス全体が停止する。
`docker exec -it` は独立した PTY を割り当てるため、コンテナの tty 設定とは無関係に動作する。

## トラブルシューティング

### claude login が必要と言われる

Claude Code v2.1.114 以降は `claude login` サブコマンドが廃止され、REPL 内の `/login` スラッシュコマンドに統一された。

```bash
docker exec -it -u autodev auto-dev-<リポジトリ名> claude
# REPL が起動したら / を入力 → login を選ぶ、または `/login` を直接タイプ
# 表示される URL をブラウザで開いて認証 → Ctrl+D で REPL を抜ける
# auto-dev は ~/.claude/.credentials.json の存在で認証完了を検知する
```

`-u autodev` を忘れると `/root/.claude/` に保存されて動かない。

### ボリューム権限エラー

`init-user.sh` が起動時に `chown` するが、ボリュームを作り直す場合:

```bash
docker compose -f docker-compose.auto-dev.yml down -v
docker compose -f docker-compose.auto-dev.yml up -d --build
```

### コンテナが停止する（WSL2 環境）

WSL2 ホストは Docker Desktop + WSL Integration で常駐させる。Ubuntu distro が idle で落ちても `docker-desktop` distro は残り、コンテナは生存する。tmux 常駐運用は廃止したので使わないこと。

**確認方法**:

```bash
docker ps                                                             # コンテナの STATUS を確認
docker exec auto-dev-<repo> cat /var/auto-dev/state/heartbeat          # heartbeat が 30s 以内に更新されているか
docker exec auto-dev-<repo> auto-dev-status                             # phase 分布 + 直近エラー
```

**対処法**:

1. Docker Desktop の自動起動が有効か確認する（Settings → General → Start Docker Desktop when you sign in）
2. WSL Integration で対象 distro（Ubuntu）がオンか確認する（Settings → Resources → WSL Integration）
3. `%USERPROFILE%\.wslconfig` に `[wsl2] vmIdleTimeout=-1` があるか確認し、なければ追加後 `wsl --shutdown`
4. 詳細手順は「WSL2 環境で 24/7 稼働させる」セクションを参照

> **補足**: コンテナは `restart: unless-stopped` + `logging.options.max-size=10m` で crash 時の復帰と log 肥大化を両立させる。heartbeat が更新されているかで hang も判定できる。

### Issue が処理されない

- `label:auto-dev` が付いているか確認
- ロックファイルが残っている場合: `/var/auto-dev/state/issue-{N}.lock` を削除（2時間で自動期限切れ）
- `GITHUB_TOKEN` の権限を確認（repo スコープ必要）

## スキル更新後の再セットアップ

auto-dev スキルのファイルを更新した後、変更を反映するための手順。
変更内容に応じて必要な対応が異なる。

### 判断フローチャート

| 変更内容 | 必要な対応 |
|---------|-----------|
| `.env.agent` の値のみ変更 | コンテナ再起動 |
| `entrypoint.sh` / `lib/*.sh` の変更 | セットアップやり直し + Docker リビルド |
| `Dockerfile` の変更 | Docker リビルド |
| `docker-compose.auto-dev.yml` の変更 | Docker リビルド |
| `templates/` 配下の変更 | セットアップやり直し + Docker リビルド |
| `SKILL.md` のみの変更 | 対応不要（次回ポーリングで自動反映） |

### .env.agent の値のみ変更した場合

```bash
# コンテナ再起動（リビルド不要）
docker compose -f docker-compose.auto-dev.yml restart
```

### スクリプト（entrypoint.sh / lib/*.sh）を変更した場合

スクリプトは Dockerfile の COPY でコンテナに焼き込まれるため、
変更を反映するには再セットアップ + リビルドが必要。

```bash
# 1. /setup-auto-dev を再実行してスクリプトをコピー
#    （Claude Code で実行、または手動でファイルコピー）

# 2. Docker リビルド & 再起動
docker compose -f docker-compose.auto-dev.yml up -d --build

# 3. Claude ログインの再確認（ボリュームを消していなければ不要）
docker exec -it -u autodev auto-dev-<リポジトリ名> claude --version
```

### テンプレート（templates/）を変更した場合

テンプレートファイル（`docker-compose.auto-dev.yml`、`env.example`）はセットアップ時に
プロジェクトルートにコピーされる。テンプレートを更新した場合、既存の環境には自動反映されない。

```bash
# 1. /setup-auto-dev を再実行してテンプレートを再生成
#    （Claude Code で実行、または手動でファイルコピー）

# 2. Docker リビルド & 再起動
docker compose -f docker-compose.auto-dev.yml up -d --build
```

### Dockerfile を変更した場合

```bash
docker compose -f docker-compose.auto-dev.yml up -d --build
```

### ボリュームを含めて完全リセットする場合

```bash
# ボリュームごと削除して再構築
docker compose -f docker-compose.auto-dev.yml down -v
docker compose -f docker-compose.auto-dev.yml up -d --build

# Claude 再ログイン（ボリュームを消したため必要）
docker exec -it -u autodev auto-dev-<リポジトリ名> claude
   # REPL で /login を入力（v2.1.114 以降は subcommand 廃止）
```
