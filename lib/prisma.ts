import { PrismaClient } from "@prisma/client";

// 開発時の HMR で PrismaClient が多重生成されるのを防ぐためのシングルトン実装。
// グローバルにインスタンスをキャッシュし、再利用する。
const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
