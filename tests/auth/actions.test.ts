import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest'
import bcrypt from 'bcryptjs'
import { testPrisma, setupTestDb, cleanDb } from '../helpers/db'

// vi.hoisted で定義した変数は vi.mock ファクトリ内で参照できる。
// vi.mock は Vitest によってファイル先頭に巻き上げられるため、
// 通常の const 定義は vi.mock ファクトリ実行時に未初期化になる。
const mockCookiesStore = vi.hoisted(() => ({
  get: vi.fn().mockReturnValue(undefined),
  set: vi.fn(),
  delete: vi.fn(),
}))

// next/navigation の redirect をモック。
// redirect() は成功パスで必ず throw するため、エラーとして捕捉する。
vi.mock('next/navigation', () => ({
  redirect: vi.fn().mockImplementation((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  }),
}))

// next/headers の cookies をモック。
vi.mock('next/headers', () => ({
  cookies: vi.fn().mockResolvedValue(mockCookiesStore),
}))

// lib/prisma をテスト用 DB に差し替える。
vi.mock('@/lib/prisma', () => ({ prisma: testPrisma }))

import { signup, login, logout } from '@/app/actions/auth'

function makeFormData(data: Record<string, string>): FormData {
  const fd = new FormData()
  Object.entries(data).forEach(([k, v]) => fd.append(k, v))
  return fd
}

beforeAll(async () => {
  await setupTestDb()
})

beforeEach(async () => {
  await cleanDb()
  vi.clearAllMocks()
  mockCookiesStore.get.mockReturnValue(undefined)
})

afterAll(async () => {
  await testPrisma.$disconnect()
})

describe('signup', () => {
  it('should return error when password is too short', async () => {
    const result = await signup(null, makeFormData({
      email: 'test@example.com',
      password: 'short',
    }))

    expect(result).toEqual({
      error: 'メールアドレスまたはパスワードの形式が正しくありません（パスワードは8文字以上）',
    })
  })

  it('should return error when email format is invalid', async () => {
    const result = await signup(null, makeFormData({
      email: 'invalid-email',
      password: 'password123',
    }))

    expect(result).toEqual({
      error: 'メールアドレスまたはパスワードの形式が正しくありません（パスワードは8文字以上）',
    })
  })

  it('should return error when email is already registered', async () => {
    const existingHash = await bcrypt.hash('password123', 4)
    await testPrisma.user.create({
      data: { email: 'existing@example.com', passwordHash: existingHash },
    })

    const result = await signup(null, makeFormData({
      email: 'existing@example.com',
      password: 'password123',
    }))

    expect(result).toEqual({
      error: 'このメールアドレスはすでに登録されています',
    })
  })

  it('should create user and set session cookie then redirect to /', async () => {
    await expect(
      signup(null, makeFormData({ email: 'new@example.com', password: 'password123' }))
    ).rejects.toThrow('NEXT_REDIRECT:/')

    const user = await testPrisma.user.findUnique({ where: { email: 'new@example.com' } })
    expect(user).not.toBeNull()

    expect(mockCookiesStore.set).toHaveBeenCalledWith(
      'session',
      expect.any(String),
      expect.objectContaining({ httpOnly: true }),
    )
  })
})

describe('login', () => {
  it('should return error when email and password are empty', async () => {
    const result = await login(null, makeFormData({ email: '', password: '' }))

    expect(result).toEqual({
      error: 'メールアドレスとパスワードを入力してください',
    })
  })

  it('should return error when user does not exist', async () => {
    const result = await login(null, makeFormData({
      email: 'nonexistent@example.com',
      password: 'password123',
    }))

    expect(result).toEqual({
      error: 'メールアドレスまたはパスワードが正しくありません',
    })
  })

  it('should return error when password is wrong', async () => {
    const correctHash = await bcrypt.hash('correctPassword', 4)
    await testPrisma.user.create({
      data: { email: 'user@example.com', passwordHash: correctHash },
    })

    const result = await login(null, makeFormData({
      email: 'user@example.com',
      password: 'wrongPassword',
    }))

    expect(result).toEqual({
      error: 'メールアドレスまたはパスワードが正しくありません',
    })
  })

  it('should create session and redirect to / on success', async () => {
    const passwordHash = bcrypt.hashSync('password123', 4)
    await testPrisma.user.create({
      data: { email: 'login@example.com', passwordHash },
    })

    await expect(
      login(null, makeFormData({ email: 'login@example.com', password: 'password123' }))
    ).rejects.toThrow('NEXT_REDIRECT:/')

    const sessions = await testPrisma.session.findMany()
    expect(sessions.length).toBeGreaterThan(0)
  })
})

describe('logout', () => {
  it('should delete session and redirect to /login', async () => {
    const passwordHash = bcrypt.hashSync('password123', 4)
    const user = await testPrisma.user.create({
      data: { email: 'logout@example.com', passwordHash },
    })

    const session = await testPrisma.session.create({
      data: {
        userId: user.id,
        expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24),
      },
    })

    // cookies().get('session') がセッション ID を返すようにセットする
    mockCookiesStore.get.mockReturnValue({ value: session.id })

    await expect(logout()).rejects.toThrow('NEXT_REDIRECT:/login')

    const found = await testPrisma.session.findUnique({ where: { id: session.id } })
    expect(found).toBeNull()
  })
})
