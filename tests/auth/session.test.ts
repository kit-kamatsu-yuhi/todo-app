import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest'
import { testPrisma, setupTestDb, cleanDb } from '../helpers/db'

// lib/prisma の prisma インスタンスをテスト用 DB に差し替える。
// session.ts は lib/prisma からインポートするため、モジュールモックが必要。
vi.mock('@/lib/prisma', () => ({ prisma: testPrisma }))

import { getSessionRecord, deleteSessionRecord } from '@/lib/auth/session'

const HASHED = '$2a$12$hashedForTestingOnly'

beforeAll(async () => {
  await setupTestDb()
})

beforeEach(async () => {
  await cleanDb()
})

afterAll(async () => {
  await testPrisma.$disconnect()
})

describe('Session レコード作成', () => {
  it('should persist a session record in the database', async () => {
    const user = await testPrisma.user.create({
      data: {
        email: 'test@example.com',
        passwordHash: HASHED,
      },
    })

    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24)
    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt,
      },
    })

    const found = await testPrisma.session.findUnique({ where: { id: session.id } })
    expect(found).not.toBeNull()
    expect(found?.userId).toBe(user.id)
  })
})

describe('getSessionRecord', () => {
  it('should return session with user when the session is not expired', async () => {
    const user = await testPrisma.user.create({
      data: {
        email: 'test@example.com',
        passwordHash: HASHED,
      },
    })

    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24)
    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt,
      },
    })

    const result = await getSessionRecord(session.id)
    expect(result).not.toBeNull()
    expect(result?.id).toBe(session.id)
    expect(result?.userId).toBe(user.id)
    expect(result?.user.email).toBe('test@example.com')
  })

  it('should return null when the session is expired', async () => {
    const user = await testPrisma.user.create({
      data: {
        email: 'expired@example.com',
        passwordHash: HASHED,
      },
    })

    // expiresAt を過去に設定して期限切れセッションを作成する
    const expiresAt = new Date(Date.now() - 1000 * 60 * 60)
    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt,
      },
    })

    const result = await getSessionRecord(session.id)
    expect(result).toBeNull()
  })

  it('should return null when the session does not exist', async () => {
    const result = await getSessionRecord('nonexistent-id')
    expect(result).toBeNull()
  })
})

describe('deleteSessionRecord', () => {
  it('should remove the session from the database', async () => {
    const user = await testPrisma.user.create({
      data: {
        email: 'delete@example.com',
        passwordHash: HASHED,
      },
    })

    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24)
    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt,
      },
    })

    await deleteSessionRecord(session.id)

    const found = await testPrisma.session.findUnique({ where: { id: session.id } })
    expect(found).toBeNull()
  })
})

describe('User 削除時の Cascade 削除', () => {
  it('should delete session records when the associated user is deleted', async () => {
    const user = await testPrisma.user.create({
      data: {
        email: 'cascade@example.com',
        passwordHash: HASHED,
      },
    })

    const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24)
    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt,
      },
    })

    await testPrisma.user.delete({ where: { id: user.id } })

    const found = await testPrisma.session.findUnique({ where: { id: session.id } })
    expect(found).toBeNull()
  })
})
