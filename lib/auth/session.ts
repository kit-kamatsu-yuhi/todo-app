import { cookies } from 'next/headers'
import { prisma } from '@/lib/prisma'

export const SESSION_COOKIE_NAME = 'session'
export const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000

// Pure DB operations (テスト可能)
export async function createSessionRecord(userId: string) {
  return prisma.session.create({
    data: {
      userId,
      expiresAt: new Date(Date.now() + SESSION_TTL_MS),
    },
  })
}

export async function getSessionRecord(sessionId: string) {
  const session = await prisma.session.findUnique({
    where: { id: sessionId },
    include: { user: true },
  })
  if (!session || session.expiresAt <= new Date()) return null
  return session
}

export async function deleteSessionRecord(sessionId: string) {
  await prisma.session.deleteMany({ where: { id: sessionId } })
}

// Next.js Cookie 統合（Server Components / Actions 内で使用）
export async function createSession(userId: string) {
  const session = await createSessionRecord(userId)
  const cookieStore = await cookies()
  cookieStore.set(SESSION_COOKIE_NAME, session.id, {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    expires: session.expiresAt,
    path: '/',
  })
}

export async function getSession() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get(SESSION_COOKIE_NAME)?.value
  if (!sessionId) return null
  return getSessionRecord(sessionId)
}

export async function deleteSession() {
  const cookieStore = await cookies()
  const sessionId = cookieStore.get(SESSION_COOKIE_NAME)?.value
  if (sessionId) await deleteSessionRecord(sessionId)
  cookieStore.delete(SESSION_COOKIE_NAME)
}
