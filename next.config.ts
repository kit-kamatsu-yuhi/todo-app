import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Prisma を使うため Node ランタイムで動かす。
  // Docker の本番イメージを小さくするため standalone 出力を有効化する。
  output: "standalone",
  // Cloud Run を認証プロキシ(gcloud run services proxy)経由で使うと、ブラウザの
  // origin(localhost:8080) と Cloud Run が付与する x-forwarded-host(実 run ホスト)が
  // 食い違い、Next.js の Server Actions が CSRF 保護で弾かれる。到達確認用に許可する。
  experimental: {
    serverActions: {
      allowedOrigins: [
        "localhost:8080",
        "todo-app-fp4dzbx5qq-an.a.run.app",
        "todo-app-159875366937.asia-northeast1.run.app",
      ],
    },
  },
};

export default nextConfig;
