import { PrismaClient } from "@prisma/client";
import { TEST_DATABASE_URL, assertTestDatabase } from "./test-db-url";

assertTestDatabase(TEST_DATABASE_URL);

export { TEST_DATABASE_URL };

export const testPrisma = new PrismaClient({
  datasources: { db: { url: TEST_DATABASE_URL } },
});

export async function setupTestDb() {
  // マイグレーションは globalSetup で一度だけ行うため、各ファイルでは接続確認に留める
  await testPrisma.$queryRaw`SELECT 1`;
}

export async function cleanDb() {
  // FK 順序に依存しないよう CASCADE で全テーブルを空にする。
  // PK はすべて cuid(TEXT) で serial/identity 列が無いため RESTART IDENTITY は不要。
  await testPrisma.$executeRawUnsafe(
    'TRUNCATE TABLE "Session", "Todo", "TodoCategory", "User" CASCADE',
  );
}
