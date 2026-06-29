# syntax=docker/dockerfile:1

# ---- Base ----
FROM node:22-slim AS base
# Prisma が OpenSSL を必要とするため slim イメージに追加する。
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# ---- Dependencies ----
FROM base AS deps
COPY package.json package-lock.json* ./
COPY prisma ./prisma
# postinstall の prisma generate を確実に走らせるため schema を先にコピーしている。
RUN npm ci

# ---- Builder ----
FROM base AS builder
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# next build 内で prisma generate も実行される（package.json の build script）。
RUN npm run build

# ---- Runner (production) ----
FROM base AS runner
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# 非 root ユーザーで実行する。
RUN groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs nextjs

# SQLite を置くデータディレクトリを作成し、実行ユーザーに権限を与える。
RUN mkdir -p /app/data && chown -R nextjs:nodejs /app/data

# standalone 出力をコピー（必要最小の node_modules を含む）。
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

# 生成済み Prisma Client のエンジン（standalone のトレースに含まれない .prisma）と
# schema をコピーする。CLI（prisma パッケージ）は #7 のランタイムでは不要。
# 業務モデル追加後にマイグレーションを起動前実行する際は CLI も同梱する。
COPY --from=builder --chown=nextjs:nodejs /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder --chown=nextjs:nodejs /app/prisma ./prisma

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# standalone 出力のエントリポイント。
CMD ["node", "server.js"]
