# シナリオ追加ガイド

このディレクトリは E2E skill が読むシナリオの置き場。1 シナリオ = 1 ディレクトリ、`scenario.md` をその中に置く。

## ディレクトリ構成

```
references/scenarios/
├── README.md           ← このファイル
├── example-login/
│   └── scenario.md
└── <your-scenario>/
    └── scenario.md
```

## scenario.md の必須セクション

```markdown
# <シナリオ名>

## 前提
- 必要な env 変数 / 事前データ / 認証状態

## ステップ
1. 自然言語で動作を 1 つずつ記述
2. ...

## Expectations
- 期待結果を箇条書き
```

H1 1 行（シナリオ名）+ 本文 3 H2 セクション（`## 前提` / `## ステップ` / `## Expectations`）を必ず含める。順序も固定する。

## ステップ記述のルール

- ステップは backend 非依存の自然言語で書く
- `@e1` のような snapshot ref、`page.click("#foo")` のような backend 固有 API は書かない
- env 変数は `${VAR}` 形式で参照する。実行時に展開される

## backend ロック（任意）

特定 backend でのみ動作するシナリオは YAML frontmatter で固定する。

```markdown
---
backend: agent-browser
---

# state 保存を伴うシナリオ
...
```

`backend: chrome-devtools` も同様に指定可能。未指定なら実行時の選択に従う。
