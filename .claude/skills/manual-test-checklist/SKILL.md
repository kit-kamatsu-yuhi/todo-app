---
name: manual-test-checklist
description: PRの差分から手動テストチェックリストを自動生成する。ブランチ固有のコミットのみを解析し、変更されたコンポーネント・画面を特定して、人間が画面を触って確認すべき項目を画面別にリストアップする。新機能追加時の動作確認、既存機能のデグレチェックの両方に対応する。
argument-hint: "<PR URL (例: https://github.com/org/repo/pull/123)>"
---

# 手動テストチェックリスト生成

## 概要

コード差分から、人間がブラウザで実際に画面を触って確認すべきチェック項目を自動生成する。新機能が正しく動作するかの確認と、既存機能にデグレが発生していないかの確認の両方を含む。生成したチェックリストは PR の description に追記する。

## ワークフロー

### ステップ1: PR URL のパースと情報取得

1. **PR URL のパース**

   `$ARGUMENTS` から PR URL を受け取る。URL から `owner`, `repo`, `number` を抽出する。

   例: `https://github.com/tieups/weclip.link/pull/8255` → `owner=tieups`, `repo=weclip.link`, `number=8255`

2. **PR メタデータの取得**

   ```bash
   gh pr view {number} --repo {owner}/{repo} --json title,body,headRefName,baseRefName,number
   ```

   取得した `baseRefName` をベースブランチ、`headRefName` を対象ブランチとして以降で使用する。

### ステップ2: プロジェクト構造の把握

1. **project-structure スキルの実行**

   ```
   run "/project-structure"
   ```

   プロジェクト構造の知識を取得し、各ディレクトリがどの画面・機能に対応するかを理解する。

### ステップ3: 差分の取得と解析

1. **PR の差分を取得する**

   ```bash
   gh pr diff {number} --repo {owner}/{repo}
   ```

2. **ブランチ固有のコミットを特定する**

   **禁止:** `git diff <ベースブランチ>` や `git diff <ベースブランチ> --name-only` は使わない。masterをマージしている場合、他ブランチで既にテスト済みの変更が含まれてしまい、テスト項目が無関係な変更で膨張する。

   代わりに、このブランチで直接コミットされた変更のみを抽出する:

   ```bash
   # ブランチ固有のコミット一覧（マージコミット除外）
   git log <ベースブランチ>..HEAD --oneline --no-merges
   ```

3. **ブランチ固有コミットで変更されたファイルを特定する**

   ```bash
   # 各コミットの変更ファイルを集約（重複排除）
   git log <ベースブランチ>..HEAD --no-merges --format="%H" | \
     xargs -I{} git diff-tree --no-commit-id --name-only -r {} | \
     sort -u
   ```

   **このファイルリストのみ**がチェックリストの対象となる。

4. **ブランチの目的に関係するコミットを絞り込む**

   ブランチ固有コミットの中に、ブランチ名と無関係な作業（別目的のコミット）が混在している場合がある。コミットメッセージとブランチ名を照合し、ブランチの本来の目的に関係するコミットのみを対象とする。無関係なコミットが含まれている場合は、ユーザーに確認する。

5. **差分の詳細取得**

   ステップ3〜4で特定したファイルに対してのみ差分を確認する:

   ```bash
   git diff <ベースブランチ>...HEAD -- <ファイルパス>
   ```

   **注意:** 3ドット（`...`）を使い、対象ファイルを明示的に指定する。

### ステップ4: 変更の分類と影響分析

取得した差分ファイルを以下の観点で分類する。

#### 4-1. パッケージの特定

変更ファイルがどのパッケージに属するか特定する:

- `frontend/packages/web/` → Web アプリ（ユーザー向け）
- `frontend/packages/admin/` → 管理画面
- `frontend/packages/common/` → 共通パッケージ（両方に影響）
- `api/` → API（画面の動作に影響）

#### 4-2. 変更カテゴリの判定

各ファイルの変更内容を読み取り、カテゴリを判定する:

| カテゴリ             | 説明                                      | チェック優先度 |
| -------------------- | ----------------------------------------- | -------------- |
| インタラクション変更 | onClick、onSubmit、イベントハンドラの変更 | 高             |
| 要素変更             | HTML要素の変更（div→button等）            | 高             |
| スタイル変更         | className、style の変更                   | 中             |
| 属性追加             | aria-label、role、data-testid の追加のみ  | 低             |
| テキスト変更         | 表示テキスト、ラベルの変更                | 中             |
| ロジック変更         | 条件分岐、状態管理の変更                  | 高             |

#### 4-3. 画面・機能へのマッピング

変更ファイルのパスから、対応する画面・機能を推定する。

**推定ルール:**

- `app/[lang]/(top)/` → トップページ
- `app/[lang]/[creatorUrl]/` → プロフィールページ
- `app/[lang]/admin/creator/` → 編集画面
- `app/[lang]/admin/analytics/` → アナリティクス画面
- `app/[lang]/signup/` → サインアップ画面
- `app/[lang]/components/layout/` → レイアウト共通（サイドバー、ヘッダー等）
- `app/[lang]/components/modal/` → モーダル共通
- `components/` → 共通コンポーネント（複数画面に影響）
- `app/(main)/notifications/` → 通知一覧（admin）
- `app/(main)/home-banners/` → ホームバナー管理（admin）
- `app/(main)/short-movies/` → ショート動画管理（admin）
- `app/(main)/step-messages/` → ステップ配信管理（admin）

上記に該当しない場合は、ファイルの内容とインポート関係を読み取って推定する。

### ステップ5: チェックリストの生成

#### 生成ルール

1. **画面単位でグルーピング** — 同じ画面に属するチェック項目はまとめる
2. **操作を具体的に記述** — 「ボタンをクリック」ではなく「○○ボタンをクリックして△△が開く」
3. **変更カテゴリに応じた項目を追加**:
   - インタラクション変更 → クリック・送信・遷移が動作するか
   - 要素変更 → 見た目が崩れていないか、クリック可能か
   - スタイル変更 → レイアウト崩れがないか
   - 属性追加のみ → 動作に影響がないことの確認（基本的に軽微）
4. **共通コンポーネント変更時** — そのコンポーネントを使用する全画面をチェック対象に含める
5. **モーダル変更時** — モーダルの開閉と内部操作の両方をチェック項目に含める

#### 出力フォーマット

```markdown
## 手動テストチェックリスト

**PR:** #<number> <title>
**ブランチ:** feature/xxx → <ベースブランチ>
**変更ファイル数:** N件

---

### Web パッケージ

#### 画面名 (`/パス`)

- [ ] チェック項目1
- [ ] チェック項目2

#### 画面名 (`/パス`)

- [ ] チェック項目1

---

### Admin パッケージ

#### 画面名 (`/パス`)

- [ ] チェック項目1

---

### 共通コンポーネント（複数画面で確認）

- [ ] コンポーネント名: チェック項目（確認画面: 画面A, 画面B）

---

### 低リスク（属性追加のみ）

以下は aria-label/role/data-testid の追加のみのため、動作への影響は軽微。
念のため該当画面で表示崩れがないことを確認:

- [ ] 画面名: 対象要素
```

### ステップ6: 補足情報の付記

チェックリストの末尾に以下を追加する:

1. **特に注意すべき変更** — ロジック変更やイベントハンドラ変更がある場合にハイライト
2. **変更の要約** — 今回の変更の目的と主な変更パターン（知っていれば）

### ステップ7: PR description への追記

生成したチェックリストを PR の description（本文）に追記する。

1. **現在の PR description を取得する**

   ```bash
   gh pr view {number} --repo {owner}/{repo} --json body --jq '.body'
   ```

2. **チェックリストセクションの追記または更新**

   PR description 内に `<!-- manual-test-checklist-start -->` ～ `<!-- manual-test-checklist-end -->` のマーカーがあるかを確認する。

   - **マーカーがある場合**: マーカー間の内容を新しいチェックリストで置換する
   - **マーカーがない場合**: description の末尾にマーカー付きでチェックリストを追記する

   追記する内容:

   ```
   <!-- manual-test-checklist-start -->
   ## 手動テストチェックリスト
   ...（生成したチェックリスト）...
   <!-- manual-test-checklist-end -->
   ```

3. **PR description を更新する**

   ```bash
   gh pr edit {number} --repo {owner}/{repo} --body '<更新後の description>'
   ```

### ステップ8: `raw/` への保存

生成したチェックリストを以下のパスにも保存する:

- **保存先**: `raw/issues/YYYY-MM-DD_<Issue番号>/manual-test-checklist.md`
- PR に関連する Issue 番号がある場合はそちらを優先。なければ PR 番号を使用する

## 注意事項

- `git diff` の内容を実際に読み取って判断する。ファイル名だけで推測しない
- **`git diff <ベースブランチ>` は絶対に使わない。** masterのマージで入った他ブランチの変更が含まれ、テスト項目が膨張するため。必ず `git log --no-merges` でブランチ固有コミットを特定し、そのコミットの変更ファイルのみを対象とする
- 共通コンポーネント（`components/` 直下）の変更は影響範囲が広いため、保守的にチェック項目を追加する
- API の変更がある場合は、そのエンドポイントを使う画面もチェック対象に含める
- 変更が属性追加のみ（aria-label、data-testid 等）の場合は「低リスク」セクションに分類し、チェックの手間を最小化する

---

## Phase 2: agent-browser によるチェックリスト実行

Phase 1 で生成したチェックリストを、`agent-browser` を使って stg 環境上で自動実行する。

### 前提条件

- stg 環境にデプロイ済みであること
- チェックリスト（`manual-test-checklist.md`）が生成済みであること
- テスト用ファイルが必要な場合は事前に準備すること

### ステップ1: テスト用ファイルの準備

チェックリストの内容に応じてテスト用ファイルを生成する。

```
raw/issues/YYYY-MM-DD_<issue番号>/test-files/
├── normal/       # 正常系テスト用ファイル
├── dangerous/    # 危険な拡張子テスト用ファイル
└── edge-cases/   # エッジケーステスト用ファイル
```

**ファイル生成方法:**

```bash
# 画像ファイル（1x1 pixel の最小画像）
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > test.png

# 動画ファイル（最小 VP8 WEBM — Playwright Chromium は H.264 非対応のため WEBM を使用）
# MP4 は Playwright Chromium でコーデック不足によりサムネイル生成に失敗する場合がある
# MP4 テストはチェックリストに「人間が手動確認」として記載する
```

### ステップ2: ブラウザでログイン

```bash
agent-browser open <stg環境URL>
# ユーザーに「ログインしてください」と伝え、ログイン完了を待つ
agent-browser snapshot -i
```

**重要:** ログインは人間に任せる。認証情報を自動入力しない。

### ステップ3: テスト実行パターン

#### Web アップロードテスト（Inspector パターン）

Web の編集画面では、ファイル入力が Inspector 内の隠し `<input type="file">` にある。

```bash
# 1. 編集画面に遷移
agent-browser open <stg環境URL>/admin/creator

# 2. Inspector を開く（対象要素をクリック）
agent-browser snapshot -i
agent-browser click @eN  # 対象の Inspector を開くボタン

# 3. 隠し input を探す
agent-browser eval "JSON.stringify([...document.querySelectorAll('input[type=file]')].map((e,i) => ({i, id:e.id, accept:e.accept, name:e.name})))"

# 4. ファイルをアップロード
agent-browser upload "input#<input-id>" /path/to/test-file

# 5. 結果確認（スナップショット + スクリーンショット）
agent-browser wait 2000
agent-browser snapshot -i
agent-browser screenshot
```

#### Admin アップロードテスト（直接 input パターン）

Admin 画面では `<input type="file">` が直接ページ上にある。

```bash
agent-browser open <admin-stg環境URL>/path/to/page
agent-browser snapshot -i
agent-browser upload "input[type=file]" /path/to/test-file
agent-browser wait 2000
agent-browser snapshot -i
```

**注意:** Admin 側は `FileUploadPolicy` のフロントエンドバリデーションが未統合の場合がある。エラーが出ない場合はバグとして記録する。

#### API テスト（パストラバーサル等）

認証が必要な API テストでは、まず正常アップロードを実行して Bearer トークンをキャプチャする。

```bash
# 1. fetch インターセプターを注入
agent-browser eval "window.__capturedAuth = null; const origFetch = window.fetch; window.fetch = async (...args) => { const req = args[0] instanceof Request ? args[0] : new Request(args[0], args[1]); const auth = req.headers.get('Authorization'); if (auth) window.__capturedAuth = auth; return origFetch.apply(window, args); };"

# 2. 正常なアップロードを1回実行してトークンをキャプチャ
# （上記のアップロードテスト手順を実行）

# 3. キャプチャしたトークンを取得
agent-browser eval "window.__capturedAuth"

# 4. API テストを実行
agent-browser eval "fetch('<resource-api-url>/v1/cloud_storages/validation', { method: 'POST', headers: { 'Authorization': '<captured-token>', 'Content-Type': 'application/json' }, body: JSON.stringify({ file_path: '<test-path>', file_type: 'image' }) }).then(r => r.json()).then(j => JSON.stringify(j))"
```

#### コードレビュー（並行実行可）

ブラウザテストと並行して、Explore エージェントでコードレビューを実行できる。

```bash
# Agent tool で Explore エージェントを起動（model: haiku）
# FE/BE のバリデーションロジック一致、許可 MIME タイプ一覧の確認等
```

### ステップ3.5: aria-label 不足の検出と追加提案

テスト実行中に `<input type="file">` や `<button>` に `aria-label` が付いていないケースを検出し、ユーザーに追加を提案する。

```bash
# 隠し input に aria-label があるか確認
agent-browser eval "JSON.stringify([...document.querySelectorAll('input[type=file]')].map((e,i) => ({i, id:e.id, ariaLabel:e.getAttribute('aria-label'), parentLabel:e.closest('label')?.textContent?.trim()})))"

# button に aria-label があるか確認
agent-browser eval "JSON.stringify([...document.querySelectorAll('button:not([aria-label])')].filter(b => !b.textContent.trim()).map((b,i) => ({i, className:b.className.slice(0,60), onclick:!!b.onclick})))"
```

**検出対象:**
- `aria-label` なしの `<input type="file">`（特に `hidden` のもの）
- テキストを持たない `<button>`（アイコンのみのボタン）
- `role` 属性のない操作可能な `<div>` / `<span>`

**提案フォーマット:**

```markdown
### アクセシビリティ改善提案
- [ ] `<ファイル名:行番号>`: `<input type="file">` に `aria-label="Upload <用途>"` を追加
- [ ] `<ファイル名:行番号>`: アイコンボタンに `aria-label="<操作内容>"` を追加
```

ユーザーが「aria 足して」と言った場合は、その場でコードを修正する。

### ステップ3.6: 並列実行戦略

テスト効率を最大化するため、独立したテストカテゴリを並列実行する。

**並列実行グループ:**

| グループ | 内容 | 実行方法 |
|---------|------|---------|
| A: ブラウザテスト | 正常系・異常系のアップロードテスト | `agent-browser`（メインスレッド） |
| B: API テスト | パストラバーサル等のサーバーサイドテスト | `agent-browser eval` でfetch実行 |
| C: コードレビュー | FE/BE バリデーション一致確認 | Agent tool（Explore, model: haiku, background） |
| D: aria 監査 | アクセシビリティ属性の過不足チェック | Agent tool（Explore, model: haiku, background） |

**実行順序:**

1. まず **C（コードレビュー）** と **D（aria 監査）** をバックグラウンドで起動
2. **A（ブラウザテスト）** をメインで実行（ログイン→正常系→異常系）
3. 正常系アップロード時に Bearer トークンをキャプチャし、**B（API テスト）** を実行
4. C・D の結果を受け取り、発見事項に統合

```
Timeline:
├─ C: コードレビュー (background) ──────────────────────┤
├─ D: aria 監査 (background) ───────────────────────────┤
├─ A: ブラウザテスト (foreground) ──────────────────┤    │
│   ├─ ログイン                                    │    │
│   ├─ 正常系テスト → Bearer トークンキャプチャ    │    │
│   ├─ B: API テスト                               │    │
│   └─ 異常系テスト                                │    │
└─ 結果統合 ─────────────────────────────────────────────┘
```

### ステップ4: 結果の記録

チェックリスト内の各項目に結果マーカーを付与する。

| マーカー | 意味 |
|---------|------|
| `[x]` | テスト合格 |
| `[?]` | 要確認（期待と異なるが致命的ではない） |
| `[!]` | バグ発見・要修正 |
| `[ ]` | 未実施 |
| `[人間]` | 人間による手動確認が必要 |

### ステップ5: 発見事項の報告

テスト完了後、チェックリストに「発見事項・要対応」セクションを追加する。

```markdown
## 発見事項・要対応

### バグ（要修正）
- [!] 具体的な問題の説明

### 要確認事項
- [?] 確認が必要な事項の説明

### 人間による手動テスト項目
- [人間] 自動テストでカバーできない項目
  - 理由: （なぜ自動化できないか）
```

### 制約事項

- **Playwright Chromium は H.264 コーデック非対応**: MP4 動画のアップロードはサムネイル生成でエラーになる場合がある。MP4 テストは「人間が手動確認」として記録する
- **空 MIME タイプのファイル**（`.bat` 等）: ブラウザが MIME タイプを空で送信するため、一部コンポーネントが無視する。発見事項として記録する
- **認証状態の維持**: `agent-browser` セッション内でログイン状態は維持される。ページ遷移しても再ログイン不要
- **並列実行**: 複数のテストカテゴリ（正常系、異常系、API テスト、コードレビュー）は可能な限り並列実行する
