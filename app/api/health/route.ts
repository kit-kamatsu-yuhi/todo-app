import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

// Prisma を使うため Edge ではなく Node ランタイムで実行する。
export const runtime = "nodejs";
// ヘルスチェックは毎回 DB 接続を確認するためキャッシュしない。
export const dynamic = "force-dynamic";

export async function GET() {
  try {
    // 最小コストで DB 接続を確認する。
    await prisma.$queryRaw`SELECT 1`;
    return NextResponse.json({ status: "ok", db: "ok" }, { status: 200 });
  } catch (error) {
    // DATABASE_URL など機密はログに出さず、エラー概要のみ記録する。
    console.error("[health] DB connection check failed", error);
    return NextResponse.json({ status: "error" }, { status: 503 });
  }
}
