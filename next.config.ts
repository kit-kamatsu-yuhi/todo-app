import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Prisma を使うため Node ランタイムで動かす。
  // Docker の本番イメージを小さくするため standalone 出力を有効化する。
  output: "standalone",
  async headers() {
    // Next.js が生成する inline script/style に対応するため、必要最小限で許容する。
    // 前提: app/ lib/ に innerHTML / dangerouslySetInnerHTML はない（'unsafe-inline' 許容の条件）。
    // DOM 直接挿入や外部リソースを導入する場合は nonce 方式への移行を再検討する（raw/issues/2026-07-30_27/plan.md 参照）。
    const scriptSrc = ["'self'", "'unsafe-inline'"];

    // next dev の HMR は eval を使うため development のときだけ許可する。
    // test や NODE_ENV 未設定の環境に 'unsafe-eval' が混入しないよう fail-closed にする。
    if (process.env.NODE_ENV === "development") {
      scriptSrc.push("'unsafe-eval'");
    }

    const contentSecurityPolicy = [
      "default-src 'self'",
      `script-src ${scriptSrc.join(" ")}`,
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data:",
      "font-src 'self'",
      "connect-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
    ].join("; ");

    return [
      {
        source: "/(.*)",
        headers: [
          {
            key: "Content-Security-Policy",
            value: contentSecurityPolicy,
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          // HSTS は HTTPS 応答でのみブラウザに記憶されるため、ローカル HTTP でも害がない。
          {
            key: "Strict-Transport-Security",
            value: "max-age=31536000; includeSubDomains",
          },
          // frame-ancestors 非対応の旧ブラウザでもクリックジャッキングを防ぐため併用する。
          {
            key: "X-Frame-Options",
            value: "DENY",
          },
          {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
          },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=()",
          },
        ],
      },
    ];
  },
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
