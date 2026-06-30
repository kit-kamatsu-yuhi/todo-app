import { PrismaClient } from "@prisma/client";
import { execSync } from "child_process";
import path from "path";

const TEST_DB_PATH = path.join(process.cwd(), "prisma", "test.db");

export const testPrisma = new PrismaClient({
  datasources: { db: { url: `file:${TEST_DB_PATH}` } },
});

export async function setupTestDb() {
  execSync("./node_modules/.bin/prisma migrate deploy", {
    env: { ...process.env, DATABASE_URL: `file:${TEST_DB_PATH}` },
  });
}

export async function cleanDb() {
  // FK 制約の順序を考慮して Session → Todo → User の順で削除する
  await testPrisma.session.deleteMany();
  await testPrisma.todo.deleteMany();
  await testPrisma.user.deleteMany();
}
