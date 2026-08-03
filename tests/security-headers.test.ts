import { describe, it, expect, vi, afterEach } from "vitest";
import type { NextConfig } from "next";

type HeaderRoutes = Awaited<ReturnType<NonNullable<NextConfig["headers"]>>>;
type HeaderRoute = HeaderRoutes[number];
type SecurityHeader = HeaderRoute["headers"][number];

const EXPECTED_PRODUCTION_CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'";

const loadHeaders = async (): Promise<HeaderRoutes> => {
  // headers() は呼び出し時に NODE_ENV を読むため、分岐検証にキャッシュ破棄は必須ではない。
  // 各テストでモジュールをクリーンに import するための防御として捨てる。
  vi.resetModules();
  const { default: nextConfig }: { default: NextConfig } =
    await import("../next.config");
  const headers = nextConfig.headers;

  if (!headers) {
    throw new Error("next.config.ts に headers() が定義されていません");
  }

  return headers();
};

const getSingleRoute = (routes: HeaderRoutes): HeaderRoute => {
  expect(routes).toHaveLength(1);
  const [route] = routes;

  if (!route) {
    throw new Error("headers() の返却値にルート定義がありません");
  }

  return route;
};

const getHeaderValue = (headers: SecurityHeader[], key: string): string => {
  const header = headers.find((currentHeader) => currentHeader.key === key);

  if (!header) {
    throw new Error(`${key} ヘッダーが見つかりません`);
  }

  return header.value;
};

const getCspDirective = (csp: string, name: string): string => {
  const directive = csp
    .split("; ")
    .find((currentDirective) => currentDirective.startsWith(`${name} `));

  if (!directive) {
    throw new Error(`${name} ディレクティブが見つかりません`);
  }

  return directive;
};

describe("next.config.ts headers()", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it("全ルートを対象にする source パターンを返す", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const route = getSingleRoute(await loadHeaders());

    expect(route.source).toBe("/(.*)");
  });

  it("本番モードで 6 つのセキュリティヘッダーを期待値で返す", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const route = getSingleRoute(await loadHeaders());

    expect(route.headers).toHaveLength(6);
    expect(getHeaderValue(route.headers, "Content-Security-Policy")).toBe(
      EXPECTED_PRODUCTION_CSP,
    );
    expect(getHeaderValue(route.headers, "X-Content-Type-Options")).toBe(
      "nosniff",
    );
    expect(getHeaderValue(route.headers, "Strict-Transport-Security")).toBe(
      "max-age=31536000; includeSubDomains",
    );
    expect(getHeaderValue(route.headers, "X-Frame-Options")).toBe("DENY");
    expect(getHeaderValue(route.headers, "Referrer-Policy")).toBe(
      "strict-origin-when-cross-origin",
    );
    expect(getHeaderValue(route.headers, "Permissions-Policy")).toBe(
      "camera=(), microphone=()",
    );
  });

  it("NODE_ENV=production のとき CSP の script-src に unsafe-eval を含めない", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const route = getSingleRoute(await loadHeaders());
    const csp = getHeaderValue(route.headers, "Content-Security-Policy");
    const scriptSrc = getCspDirective(csp, "script-src");

    expect(scriptSrc).not.toContain("'unsafe-eval'");
  });

  it("NODE_ENV=development のとき CSP の script-src に unsafe-eval を含める", async () => {
    vi.stubEnv("NODE_ENV", "development");
    const route = getSingleRoute(await loadHeaders());
    const csp = getHeaderValue(route.headers, "Content-Security-Policy");
    const scriptSrc = getCspDirective(csp, "script-src");

    expect(scriptSrc).toContain("'unsafe-eval'");
  });
});
