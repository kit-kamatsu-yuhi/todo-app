import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    include: ["tests/**/*.{test,spec}.{ts,tsx}"],
    // DB 統合テストの並列実行競合を防ぐためシングルプロセスで実行する
    pool: "forks",
    poolOptions: {
      forks: {
        singleFork: true,
      },
    },
    // singleFork はプロセス数の制約のみで、ファイル間の非同期 interleaving は防げない。
    // テストファイルが共有のファイルベース SQLite (prisma/test.db) を使うため、
    // 各ファイルの beforeEach:cleanDb() が他ファイルの実行中データを削除してしまう
    // レースコンディションを防ぐためファイル単位も直列実行にする。
    fileParallelism: false,
    // Prisma binary の cold start（初回18秒程度）に対応するため延長する
    hookTimeout: 60000,
    // bcrypt cost=12 は 1回あたり ~1.5 秒かかるためデフォルトの 5s では不足する
    testTimeout: 15000,
  },
});
