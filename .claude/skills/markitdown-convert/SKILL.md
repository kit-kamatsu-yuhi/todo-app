---
name: markitdown-convert
description: Microsoft markitdown で PDF / Word / Excel / PowerPoint / オーディオ / YouTube URL を Markdown へ変換する。ファイルや URL を Markdown に変換したいとき、要約のために Markdown 化したいときに使う。 TRIGGER when: ファイル/URL を Markdown 化したい、PDF/Word/Excel/PowerPoint/オーディオ/YouTube を md に変換したい。DO NOT TRIGGER: 既に Markdown のファイルを再処理したい場合。
---

# markitdown-convert

## 概要

Microsoft [markitdown](https://github.com/microsoft/markitdown) を uv 経由で呼び出し、PDF / Office 文書 / オーディオ / YouTube URL を Markdown に変換する。変換結果は stdout または `-o` で指定したファイルに出力する。

## トリガー条件

TRIGGER when いずれかに該当する場合、必ずこのスキルを起動する（スキップ不可）。

- ファイルを Markdown に変換したいとき
- URL（特に YouTube）の内容を Markdown 化したいとき
- PDF を md にしたいとき
- Word / Excel / PowerPoint を Markdown 化して要約や差分比較に使いたいとき
- オーディオファイルを文字起こし + Markdown 化したいとき
- 別のスキルや LLM に食わせるため素材を Markdown 化したいとき

## 対応フォーマット

| 種別 | 拡張子 / 形式 |
|------|--------------|
| PDF | `.pdf` |
| Word | `.docx` |
| Excel | `.xlsx` |
| PowerPoint | `.pptx` |
| オーディオ | `.mp3`, `.wav` |
| 動画 URL | YouTube URL |

## 実行手順

### 初回セットアップ

スキルディレクトリで `uv sync` を実行する。`.venv` と `uv.lock` が生成される。

```bash
cd .claude/skills/markitdown-convert && uv sync
```

### 変換

リポジトリルートに戻り、`uv run --project` でスキルの仮想環境を指定して `.claude/skills/markitdown-convert/scripts/convert.py` を呼ぶ。

```bash
uv run --project .claude/skills/markitdown-convert python .claude/skills/markitdown-convert/scripts/convert.py <入力> [-o output.md]
```

- `<入力>` はファイルパスまたは URL
- `-o` 未指定なら stdout に出力する
- `-o` を指定すると親ディレクトリを自動生成してファイルに書き込む

## 注意事項

- 生成した Markdown ファイルは **git add しない**。受入基準で明記されており、コミットしてはならない
- 音声変換はローカル Whisper 等の依存を使うためオプション。初回変換時に環境側の ffmpeg 等が必要な場合がある
- YouTube 変換は `pytube` 系の実装に依存する。YouTube 側の仕様変更で失敗することがあり、その場合は markitdown 側の更新を待つ

## 使用例

PDF をファイルに書き出す。

```bash
uv run --project .claude/skills/markitdown-convert python .claude/skills/markitdown-convert/scripts/convert.py report.pdf -o report.md
```

Word を stdout に流してパイプで別ツールへ渡す。

```bash
uv run --project .claude/skills/markitdown-convert python .claude/skills/markitdown-convert/scripts/convert.py spec.docx
```

YouTube URL を要約用 Markdown に変換する。

```bash
uv run --project .claude/skills/markitdown-convert python .claude/skills/markitdown-convert/scripts/convert.py https://www.youtube.com/watch?v=XXXX -o transcript.md
```
