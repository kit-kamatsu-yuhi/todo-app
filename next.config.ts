import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // SQLite + Prisma を使うため Node ランタイムで動かす。
  // Docker の本番イメージを小さくするため standalone 出力を有効化する。
  output: "standalone",
};

export default nextConfig;
