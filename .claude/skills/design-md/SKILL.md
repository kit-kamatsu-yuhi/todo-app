---
name: design-md
description: |
  google-labs-code/design.md の CLI (`@google/design.md`) を使って DESIGN.md の lint / diff / export / spec を運用するための skill。
  TRIGGER when: 「DESIGN.md を lint」「DESIGN.md の構造を検証」「デザイントークンを Tailwind に export」「DESIGN.md を DTCG tokens に変換」「design.md 仕様を確認」「DESIGN.md の差分を比較」
  DO NOT TRIGGER when: 一般的なコード lint (→ 各言語の lint)、UI/UX 実装 (→ ui-ux-pro-max)、CSS の記述 (→ ui-ux-pro-max)、ブランディングそのものの意思決定 (→ design)。
---

# design-md

DESIGN.md ファイル (YAML frontmatter 形式のデザイントークン + Markdown prose) を `@google/design.md` CLI で検証・変換する。本 skill は `Clickan/exoloop` から consumer に配布される。

## install

`@google/design.md` は repo root の devDependency として固定バージョンで導入する。consumer プロジェクトは `pnpm install` で取り込むだけでよい。

```bash
pnpm add -D @google/design.md@0.1.1
```

本体 bin は `design.md` (ドット付き)。package.json の `scripts` では `design-md` / `design-md:lint` (ハイフン) を公開する。

```json
{
  "scripts": {
    "design-md": "design.md",
    "design-md:lint": "design.md lint DESIGN.md"
  }
}
```

### pnpm minimumReleaseAge との共存

workspace に `minimumReleaseAge` (14 日程度の supply-chain guard) が設定されている場合、`@google/design.md` はリリース頻度が高く引っかかることがある。`pnpm-workspace.yaml` に以下を追加して明示的に除外する。

```yaml
minimumReleaseAge: 20160
minimumReleaseAgeExclude:
  - "@google/design.md"
```

除外対象は最小限にする。追加した理由と対象パッケージは commit body と PR 本文に書き残す。

## commands

```bash
pnpm design-md lint DESIGN.md                    # 構造と WCAG コントラストを検証
pnpm design-md diff DESIGN.md DESIGN-next.md     # 2 ファイル間のトークン差分
pnpm design-md export --format tailwind DESIGN.md  # Tailwind theme (tailwind.config.ts) に変換
pnpm design-md export --format dtcg DESIGN.md     # DTCG tokens.json に変換
pnpm design-md spec                               # 仕様書全文を stdout へ
```

exit code は CI で評価する。`lint` は errors > 0 のとき非 0 を返す。warning / info は 0 を維持する。

## 運用パターン（参考）

リポジトリのデザインシステムを `DESIGN.md` に集約し、派生（教材・サブブランド・コンポーネント別）を別ファイルで持つ構成を推奨する。

- `DESIGN.md` — リポジトリ全体のデザインシステム。google-labs-code/design.md 仕様（YAML frontmatter + 8 セクション順）を厳密に守る
- 派生 `DESIGN_*.md` — 教材・サブブランド派生。本文は prose 主体になることが多い
- PR を作る前に `pnpm design-md:lint` を必ず通す (errors = 0)
- トークンを追加 / 変更したときは同じ PR 内で CSS / Tailwind / 実装側の反映もまとめる

派生ドキュメント（prose 主体の md）は **section-order warning を受け入れて良い**。error 0 / warning 込みで運用する場合は PR 本文で warning 件数と理由を明記する。wiki 階層管理を併用する場合は frontmatter 規約（例: `title/genre/summary/updated`）を省略しない。

## troubleshooting

| 症状 | 原因 | 対処 |
|------|------|------|
| `broken-ref` error | `{colors.xxx}` の参照先が frontmatter に存在しない | 参照名を frontmatter の実キーと揃える。`colors.ink` を参照するなら `colors:` に `ink:` を追加 |
| `missing-primary` error | `colors:` に `primary` キーが無い | `primary` を必ず定義する (spec 要件) |
| `missing-typography` warning | typography token が 0 件 | 最低 1 件 (例: `body-md`) を定義 |
| `section-order` warning | セクションの順序が Overview → Colors → Typography → Layout → Elevation & Depth → Shapes → Components → Do's and Don'ts と一致しない | 見出し順を仕様に揃える。派生ドキュメントの場合は warning を受け入れて PR 本文に明記 |
| `contrast-ratio` warning | 定義した色の組み合わせが WCAG AA (4.5:1) を下回る | 組み合わせを見直すか、意図した装飾用途であれば PR 本文で明示 |
| `Command failed: design-md: command not found` | scripts が `design-md` (ハイフン) を直接呼んでいる | bin は `design.md` (ドット)。`"design-md": "design.md"` のように script 名と bin 名を分ける |
| `ERR_PNPM_NO_MATURE_MATCHING_VERSION` | pnpm の `minimumReleaseAge` で新しいリリースが弾かれる | `minimumReleaseAgeExclude` に対象パッケージを追加 (上記 install 節参照) |

## ファイル配置と参照

- CLI 実行時の `DESIGN.md` はリポジトリ直下を標準パスとする。
- 派生ドキュメント (教材など) に lint を掛けるときは `pnpm design-md lint <relative-path>` と明示する。
- `design-md:lint` スクリプトはルート `DESIGN.md` 固定で運用する。派生ファイル用に別 script を足す場合は `design-md:lint:course` のように意味ベースで命名する。
