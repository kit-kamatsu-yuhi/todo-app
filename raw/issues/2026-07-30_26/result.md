# Issue #26 対応記録: next 15.5.22 更新と npm audit 結果

- date: 2026-07-30
- branch: feature/26-next-security-patch

## 実施内容

- next / eslint-config-next を 15.5.19 → 15.5.22 に更新（固定バージョン表記を維持）
- `npm audit fix` で dev 依存の推移的脆弱性を更新（brace-expansion 1.1.17 / 2.1.3 / 5.0.8、@eslint/eslintrc 3.3.6、nanoid 3.3.16。vite 配下のネスト postcss は削除されルートの 8.5.25 に dedupe）
- package.json に `overrides` を追加: `postcss: 8.5.25`、`sharp: 0.35.3`
  - postcss: next 15.5.22 が 8.4.31 を exact pin しており、audit fix では更新不能のため同一メジャー内で強制更新（GHSA-6g55-p6wh-862q / GHSA-r28c-9q8g-f849 / GHSA-qx2v-qp2m-jg93 の解消）
  - sharp: next の optionalDependencies `^0.34.3` の範囲外となる 0.35.3 へ強制更新（GHSA-f88m-g3jw-g9cj、libvips 継承 CVE の解消）

## npm audit 結果

| 実行 | critical | high | moderate | low |
|------|----------|------|----------|-----|
| `npm audit`（フル） | 0 | 12 | 0 | 0 |
| `npm audit --omit=dev`（production） | 0 | 0 | 0 | 0 |

production 依存ツリーは全 severity 0 件。next 本体の advisories（GHSA-m99w-x7hq-7vfj / GHSA-89xv-2m56-2m9x / GHSA-68g3-v927-f742 ほか）は 15.5.22 で解消済み。

## 残存リスクの判断（要ユーザー確認）

フル audit に残る high 12 件はすべて単一 advisory **GHSA-mh99-v99m-4gvg**（brace-expansion <=5.0.7 の unbounded expansion DoS）の dev 連鎖による重複計上。

- 経路は eslint 9 → minimatch 3.x → brace-expansion 1.1.17 と、@vitest/coverage-v8 → test-exclude → glob → minimatch 9.x → brace-expansion 2.1.3 の 2 本。いずれも devDependencies のみで本番ランタイムに載らない
- 1.x / 2.x へのバックポートは存在せず（registry 確認済み）、解消には eslint 10 への破壊的更新が必要
- 判断: 本 Issue では許容し、eslint 10 移行（`next lint` の Next.js 16 での削除と合わせた ESLint 移行）を別 Issue として扱う
- TODO: eslint 10 移行のフォローアップ Issue を起票する（起票時にここへ Issue 番号を追記する）

## 回帰確認

| 確認 | 結果 |
|------|------|
| `npm run build`（prisma generate + next build） | 成功（静的ページ 6/6、型チェック・lint 通過） |
| `npm run test`（vitest、PostgreSQL 必須の既存仕様） | 100/100 passed |
| `npm run test:pg`（scripts/test-with-postgres.sh） | 100/100 passed |
| `npm run lint`（eslint-config-next 15.5.22） | No warnings or errors |

lockfile 差分は next 系・sharp（@img/sharp-* 27 プラットフォーム）・postcss・nanoid・brace-expansion・@eslint/eslintrc のみで、意図しないパッケージの混入なし。

## 運用メモ

- next を更新するたびに overrides（postcss / sharp）の要否を再確認する。next 側が pin を更新したら overrides は削除する
- sharp は next/image の画像最適化用 optional 依存。現状 next/image は未使用だが、使用開始時は Cloud Run 上での動作確認に含める
