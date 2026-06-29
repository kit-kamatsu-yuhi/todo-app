---
name: gitleaks
description: |
  gitleaks を使った secret 漏洩検出の install / lefthook 設定 / allowlist 運用 / troubleshoot を体系化した skill。
  TRIGGER when: 「gitleaks を入れて」「gitleaks を設定して」「secret 検査を追加」「.gitleaks.toml を更新」「gitleaks の false positive を抑止」
  DO NOT TRIGGER when: 他セキュリティツール (trivy, trufflehog 等) の導入、Issue 単位の実装 (→ start-issue)。
---

# gitleaks

リポジトリ内の secret（AWS キー、API トークン、DB 接続文字列、GCP サービスアカウント等）を commit 前に検出するための skill。本 skill は `Clickan/exoloop` が lefthook と併せて consumer に配布する。

**本 skill の守備範囲**:
- ローカル install（macOS / Linux / Windows）
- `.gitleaks.toml` の最小構成
- `lefthook.yml` への gitleaks コマンド追加
- false positive の抑止手順（allowlist / `.gitleaksignore` / stopwords）
- よく出るエラーの対処

**守備範囲外**:
- CI での全履歴スキャン（別 skill / 別 Issue で扱う）
- GitHub push protection や Secret Scanning の設定

## install

gitleaks は Go バイナリ単体で動く。以下のいずれかで導入する。

| 環境 | コマンド |
|------|---------|
| macOS (Homebrew) | `brew install gitleaks` |
| Debian / Ubuntu  | `sudo apt-get install -y gitleaks`（リポジトリにより無い場合あり） |
| Arch Linux       | `sudo pacman -S gitleaks` |
| Windows (scoop)  | `scoop install gitleaks` |
| 全環境共通       | https://github.com/gitleaks/gitleaks/releases から tar.gz をダウンロードし `$PATH` に配置 |

導入確認:

```bash
gitleaks version
```

### install 不要の escape hatch

開発者の環境に gitleaks が一時的に入っていない場合でも commit を止めないため、`scripts/hooks/gitleaks-protect.sh` ラッパーが以下の順にフォールバックする:

1. `GITLEAKS_ENABLE=0` が指定されていれば即 exit 0（検査 skip）
2. `gitleaks` が PATH に無ければ WARN + exit 0
3. それ以外は `gitleaks protect --staged --redact --config .gitleaks.toml` を実行

一時的に検査を skip したい場合は `GITLEAKS_ENABLE=0 git commit ...` のように env を渡す。

## 最小 config (`.gitleaks.toml`)

```toml
title = "my-project gitleaks config"

[extend]
useDefault = true  # gitleaks 内蔵ルール（AWS / GCP / Slack / JWT 等）を全て有効化

[allowlist]
description = "プロジェクト共通の allowlist"
paths = [
  '''tests/.*/fixtures/.*''',        # テスト用の意図的ダミー secret
  '''\.gitleaks\.toml''',            # 本ファイル自体（example を含むため）
]
regexes = [
  # 例: placeholder な AWS dummy key
  '''AKIA[0-9A-Z]{16}_EXAMPLE''',
]
stopwords = ["example", "placeholder", "dummy", "sample"]
```

### allowlist の書き分け

| 書き方 | 意図 | 使うタイミング |
|--------|------|---------------|
| `paths` | 特定ファイル全体を除外 | fixture / sample / ドキュメント |
| `regexes` | 検出値にマッチしたら除外 | placeholder 文字列パターン |
| `stopwords` | 検出値に含まれる単語で除外 | `EXAMPLE` / `PLACEHOLDER` を含む値 |

## lefthook.yml への組み込み

```yaml
pre-commit:
  parallel: true
  commands:
    gitleaks:
      run: bash scripts/hooks/gitleaks-protect.sh
```

`scripts/hooks/gitleaks-protect.sh` は上記 install 節のフォールバック挙動を持つラッパー。exoloop を install すると `setup-exoloop` が consumer の `scripts/hooks/gitleaks-protect.sh` を配布する。

## `.gitleaksignore`

commit 単位で個別に ignore するときは `.gitleaksignore` を使う。形式:

```
<commit-sha>:<file-path>:<rule-id>:<start-line>
```

fingerprint は gitleaks の出力 `Fingerprint:` 行からコピーする。追加する時は必ず「false positive だと確認した上で追加する」運用ルールを skill にも明記する。

## false positive 対応フロー

1. `gitleaks detect --source . --no-git -v` で再現する
2. 検出値が placeholder か本物かを確認する（本物なら rotate + 履歴から除去を優先）
3. false positive と判断したら、優先順位の高い対応から:
   1. `stopwords` に追加（単語ベース）
   2. `regexes` に追加（値のパターンベース）
   3. `paths` に追加（ファイル全体ベース）
   4. `.gitleaksignore` に fingerprint 追加（1 コミット限定）
4. 再度 `gitleaks detect` で通ることを確認し、config 変更を PR に含める

## よくあるエラーと対処

| 症状 | 原因 | 対処 |
|------|------|------|
| `command not found: gitleaks` | 未インストール | brew / apt / release page から install |
| `error: invalid config: ...` | `.gitleaks.toml` の TOML 構文エラー | `gitleaks detect --config .gitleaks.toml` で再検証 |
| commit 時に毎回止まる | `protect --staged` が stagedfile に毎回ヒット | allowlist 設計ミス。paths を見直す |
| CI で全履歴スキャンが重い | `gitleaks detect` が全 commit を走査 | `--log-opts="--since=2026-01-01"` で期間を区切る |

## CLI チートシート

```bash
# staged diff のみ（pre-commit 用途）
gitleaks protect --staged --redact --config .gitleaks.toml

# working tree 全体（git 非依存の scan）
gitleaks detect --source . --no-git -v

# 全履歴 scan
gitleaks detect --source . -v

# 1 ファイルだけ scan
gitleaks detect --source path/to/file --no-git -v
```

## 運用ノート

- `--redact` を常用して検出値を masked 表示にする（ログに平文を残さない）
- `protect --staged` は pre-commit 限定。push 時や CI で全履歴を見るなら `detect` を使う
- 検出値が本物だった場合は、`git filter-repo` 等で履歴から除去した後に該当 secret を rotate する。`.gitleaksignore` は本物検出を抑える用途では使わない
