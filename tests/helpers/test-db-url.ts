// テスト用 DB 接続文字列とガード。db.ts と global-setup.ts で共有する
// （PrismaClient を setup プロセスに持ち込まないよう、URL だけを別モジュールに切り出す）。

const DEFAULT_TEST_DATABASE_URL =
  "postgresql://todo:todo@localhost:15432/todo_test?schema=public";

export const TEST_DATABASE_URL =
  process.env.TEST_DATABASE_URL ?? DEFAULT_TEST_DATABASE_URL;

// migrate deploy / TRUNCATE は破壊的なため、誤って開発・本番 DB に向けないよう
// 対象 DB 名が *_test で終わることを必須にする（ALLOW_NON_TEST_DATABASE=1 で明示解除）。
export function assertTestDatabase(url: string): void {
  if (process.env.ALLOW_NON_TEST_DATABASE === "1") return;
  const dbName = new URL(url).pathname.replace(/^\//, "");
  if (!dbName.endsWith("_test")) {
    throw new Error(
      `破壊的なテストセットアップを非テスト DB "${dbName}" に対して実行しようとしました。` +
        `DB 名を *_test にするか、意図的な場合は ALLOW_NON_TEST_DATABASE=1 を設定してください。`,
    );
  }
}
