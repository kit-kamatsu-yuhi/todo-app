---
name: gws
description: Google Workspace CLI (gws) を使って Google Docs・Drive・Sheets・Gmail・Calendar などを操作するスキル。Google Docs の読み取り・書き込み、Drive ファイル管理、Sheets データ操作などに使用する。TRIGGER when: ユーザーが「Google Docs を読みたい」「Google Drive のファイルを操作したい」「gws で〜したい」「Google Workspace の〜を取得したい」と言ったとき。
allowed-tools: Bash(gws:*)
---

# Google Workspace CLI (gws)

[googleworkspace/cli](https://github.com/googleworkspace/cli) — One CLI for all of Google Workspace. Drive・Gmail・Calendar・Sheets・Docs などに統一 CLI でアクセスできる。

## インストール

```bash
# Homebrew (推奨)
brew install googleworkspace-cli

# または npm
npm install -g @googleworkspace/cli

# バージョン確認
gws --version
```

## 認証セットアップ

### 方法 1: `gws auth setup`（gcloud CLI がある場合・推奨）

GCP プロジェクト作成・API 有効化・OAuth クライアント設定・ログインを一括実行する。

**前提条件:**
- `gcloud` CLI がインストール済みであること
- `gcloud auth login` で gcloud 自体が認証済みであること

```bash
# gcloud がなければ先にインストール
brew install --cask google-cloud-sdk
gcloud auth login   # gcloud の認証（初回のみ）

# gws の全自動セットアップ
gws auth setup              # 新規 GCP プロジェクトを作成してセットアップ
gws auth setup --login      # セットアップ完了後にそのまま gws auth login まで実行
gws auth setup --project my-project-id  # 既存プロジェクトを使う
gws auth setup --dry-run    # 実際には何もせず、実行内容をプレビューする
```

**`gws auth setup` が行うこと（順に実行）:**
1. GCP プロジェクトの作成（または `--project` で指定した既存プロジェクトを使用）
2. Google Workspace 関連 API の有効化（Docs / Drive / Sheets / Gmail / Calendar 等）
3. OAuth 2.0 クライアント ID の作成
4. `~/.config/gws/client_secret.json` への配置
5. `--login` 指定時はそのまま OAuth ログインまで完了する

### 方法 2: 手動セットアップ（gcloud CLI なし）

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. 「APIとサービス」→「ライブラリ」で必要な API を有効化（例: Google Docs API）
3. 「認証情報」→「OAuth 2.0 クライアント ID」を作成（アプリの種類: **デスクトップアプリ**）
4. JSON をダウンロード → `~/.config/gws/client_secret.json` に配置
5. `gws auth login` でブラウザ OAuth 認証

```bash
mkdir -p ~/.config/gws
cp ~/Downloads/client_secret_*.json ~/.config/gws/client_secret.json
gws auth login    # ブラウザが開いて OAuth 認証
```

### 認証状態の確認・管理

```bash
# 認証状態を確認
gws auth status

# 認証済みかどうかをスクリプトで判定
gws auth status | python3 -c "import sys,json; d=json.load(sys.stdin); print('OK' if d['auth_method'] != 'none' else 'NOT AUTHENTICATED')"

# 認証情報をエクスポート（バックアップ用）
gws auth export

# ログアウト（トークンと認証情報を削除）
gws auth logout
```

## Google Docs

### ドキュメントを読む

```bash
# ドキュメント ID は URL から取得: docs.google.com/document/d/<DOCUMENT_ID>/edit
DOC_ID="1ZTpou5UxuUQqBdIwWRm0xhLwhjWSK8OmBeJVAzJiUCw"

# ドキュメント全体を取得 (JSON)
gws docs documents get --params "{\"documentId\": \"$DOC_ID\"}"

# テキストのみ抽出
gws docs documents get --params "{\"documentId\": \"$DOC_ID\"}" \
  | python3 -c "
import sys, json
doc = json.load(sys.stdin)
def extract_text(elem):
    if isinstance(elem, dict):
        if 'textRun' in elem:
            return elem['textRun'].get('content', '')
        return ''.join(extract_text(v) for v in elem.values())
    if isinstance(elem, list):
        return ''.join(extract_text(e) for e in elem)
    return ''
print(extract_text(doc.get('body', {})))
"
```

### ドキュメントに書き込む

```bash
DOC_ID="<document-id>"

# テキストを末尾に追記
gws docs +write --document-id "$DOC_ID" --text "追記するテキスト"

# Discovery API 経由でバッチ更新
gws docs documents batchUpdate \
  --params "{\"documentId\": \"$DOC_ID\"}" \
  --body '{
    "requests": [{
      "insertText": {
        "location": {"index": 1},
        "text": "先頭に挿入するテキスト\n"
      }
    }]
  }'
```

### スキーマ確認

```bash
gws schema docs.documents.get      # 利用可能なパラメータを確認
gws docs --help                    # サブコマンド一覧
gws docs documents --help          # documents サブコマンド詳細
```

## Google Drive

```bash
# ファイル一覧
gws drive files list --params '{"pageSize": 20}'

# ファイル検索
gws drive files list --params '{"q": "name contains '\''report'\'' and mimeType='\''application/vnd.google-apps.document'\''"}'

# ファイルメタデータ取得
gws drive files get --params '{"fileId": "<file-id>", "fields": "id,name,mimeType,modifiedTime"}'

# ファイルダウンロード (export)
gws drive files export --params '{"fileId": "<file-id>", "mimeType": "text/plain"}' -o output.txt
```

## Google Sheets

```bash
SHEET_ID="<spreadsheet-id>"

# データ取得
gws sheets spreadsheets values get \
  --params "{\"spreadsheetId\": \"$SHEET_ID\", \"range\": \"Sheet1!A1:Z100\"}"

# データ書き込み
gws sheets spreadsheets values update \
  --params "{\"spreadsheetId\": \"$SHEET_ID\", \"range\": \"Sheet1!A1\", \"valueInputOption\": \"USER_ENTERED\"}" \
  --body '{"values": [["Name", "Value"], ["Alice", "100"]]}'

# 行追加
gws sheets spreadsheets values append \
  --params "{\"spreadsheetId\": \"$SHEET_ID\", \"range\": \"Sheet1\", \"valueInputOption\": \"USER_ENTERED\"}" \
  --body '{"values": [["新しい行", "値"]]}'
```

## Gmail

```bash
# メール一覧 (最新20件)
gws gmail users messages list --params '{"userId": "me", "maxResults": 20}'

# メール内容取得
gws gmail users messages get --params '{"userId": "me", "id": "<message-id>", "format": "full"}'

# メール送信
gws gmail users messages send --params '{"userId": "me"}' \
  --body '{
    "raw": "'$(echo -e "To: recipient@example.com\nSubject: Test\n\nHello World" | base64)'"
  }'
```

## Google Calendar

```bash
# カレンダー一覧
gws calendar calendarList list --params '{"maxResults": 10}'

# イベント一覧
gws calendar events list \
  --params '{"calendarId": "primary", "maxResults": 10, "orderBy": "startTime", "singleEvents": true}'

# イベント作成
gws calendar events insert \
  --params '{"calendarId": "primary"}' \
  --body '{
    "summary": "Meeting",
    "start": {"dateTime": "2026-04-20T10:00:00+09:00"},
    "end": {"dateTime": "2026-04-20T11:00:00+09:00"}
  }'
```

## 汎用パターン

### スキーマ確認

```bash
# 任意のリソース・メソッドのパラメータを確認
gws schema <service>.<resource>.<method>
# 例: gws schema docs.documents.batchUpdate
# 例: gws schema drive.files.list
# 例: gws schema sheets.spreadsheets.values.get
```

### 出力フォーマット

```bash
# JSON (デフォルト)
gws docs documents get --params '{"documentId": "..."}' --format json

# YAML
gws docs documents get --params '{"documentId": "..."}' --format yaml

# テーブル
gws drive files list --params '{"pageSize": 5}' --format table
```

### ページネーション

```bash
# 全件取得 (NDJSON 形式で出力)
gws drive files list --params '{"pageSize": 100}' --page-all

# 最大ページ数を制限
gws drive files list --params '{"pageSize": 100}' --page-all --page-limit 5
```

## トラブルシューティング

| 症状 | 対処 |
|------|------|
| `auth_method: none` | `gws auth login` で再認証 |
| `client_config_exists: false` | `~/.config/gws/client_secret.json` を配置する |
| `403 Forbidden` | GCP で該当 API が有効になっているか確認 |
| `invalid_grant` | `gws auth login` でトークンを再取得 |

## 参照

- [GitHub: googleworkspace/cli](https://github.com/googleworkspace/cli)
- [Google Docs API Reference](https://developers.google.com/docs/api/reference/rest)
- [Google Drive API Reference](https://developers.google.com/drive/api/reference/rest/v3)
