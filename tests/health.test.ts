import { describe, it, expect, vi, beforeEach } from "vitest";

// 実 DB に依存させないため、prisma クライアントをモックして $queryRaw を resolve させる。
vi.mock("@/lib/prisma", () => ({
  prisma: {
    $queryRaw: vi.fn().mockResolvedValue([{ "1": 1 }]),
  },
}));

import { GET } from "@/app/api/health/route";
import { prisma } from "@/lib/prisma";

describe("GET /api/health", () => {
  beforeEach(() => {
    vi.mocked(prisma.$queryRaw).mockResolvedValue([{ "1": 1 }]);
  });

  it("DB 接続成功時に 200 と status:ok を返す", async () => {
    const res = await GET();
    expect(res.status).toBe(200);

    const body = await res.json();
    expect(body).toEqual({ status: "ok", db: "ok" });
  });

  it("DB 接続失敗時に 503 と status:error を返す", async () => {
    vi.mocked(prisma.$queryRaw).mockRejectedValueOnce(new Error("connection failed"));
    const res = await GET();
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body).toEqual({ status: "error" });
  });
});
