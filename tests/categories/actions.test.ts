import { describe, it, expect, beforeAll, beforeEach, afterAll, vi } from 'vitest'
import { testPrisma, setupTestDb, cleanDb } from '../helpers/db'

// next/navigation の redirect をモック。
// redirect() は必ず throw するため、エラーとして捕捉する（auth テストと同じ方式）。
vi.mock('next/navigation', () => ({
  redirect: vi.fn().mockImplementation((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  }),
}))

// next/cache の revalidatePath をモック。
// createCategory / deleteCategory が呼ぶため、未モックだとテスト環境でエラーになる。
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))

// lib/auth/session の getSession をモックしてログインユーザーを制御する。
vi.mock('@/lib/auth/session', () => ({ getSession: vi.fn() }))

// lib/prisma をテスト用 DB に差し替える。
vi.mock('@/lib/prisma', () => ({ prisma: testPrisma }))

import { createCategory, deleteCategory } from '@/app/actions/categories'
import { getSession } from '@/lib/auth/session'

const mockGetSession = vi.mocked(getSession)

function makeFormData(data: Record<string, string>): FormData {
  const fd = new FormData()
  Object.entries(data).forEach(([k, v]) => fd.append(k, v))
  return fd
}

async function createUser(email: string) {
  return testPrisma.user.create({
    data: { email, passwordHash: 'dummy-hash' },
  })
}

beforeAll(async () => {
  await setupTestDb()
})

beforeEach(async () => {
  await cleanDb()
  vi.clearAllMocks()
})

afterAll(async () => {
  await testPrisma.$disconnect()
})

describe('createCategory', () => {
  it('should create a category linked to the user and return null on valid name', async () => {
    const user = await createUser('create@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createCategory(null, makeFormData({ name: '仕事' }))

    expect(result).toBeNull()

    const categories = await testPrisma.todoCategory.findMany({ where: { userId: user.id } })
    expect(categories).toHaveLength(1)
    expect(categories[0]).toMatchObject({
      userId: user.id,
      name: '仕事',
    })
  })

  it('should return error and not create a category when name is empty', async () => {
    const user = await createUser('empty@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createCategory(null, makeFormData({ name: '' }))

    expect(result).toEqual({ error: 'カテゴリ名を入力してください' })

    const count = await testPrisma.todoCategory.count()
    expect(count).toBe(0)
  })

  it('should return error and not create a category when name is only whitespace', async () => {
    const user = await createUser('whitespace@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createCategory(null, makeFormData({ name: '   ' }))

    expect(result).toEqual({ error: 'カテゴリ名を入力してください' })

    const count = await testPrisma.todoCategory.count()
    expect(count).toBe(0)
  })

  it('should return a length-specific error when the name exceeds 50 characters', async () => {
    const user = await createUser('toolong@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createCategory(null, makeFormData({ name: 'あ'.repeat(51) }))

    expect(result).toEqual({ error: 'カテゴリ名は50文字以内で入力してください' })

    const count = await testPrisma.todoCategory.count()
    expect(count).toBe(0)
  })

  it('should return error and not create a category when not logged in', async () => {
    mockGetSession.mockResolvedValue(null)

    const result = await createCategory(null, makeFormData({ name: '未ログインのカテゴリ' }))

    expect(result).toEqual({ error: 'ログインが必要です' })

    const count = await testPrisma.todoCategory.count()
    expect(count).toBe(0)
  })
})

describe('deleteCategory', () => {
  it('should delete own category from the DB', async () => {
    const user = await createUser('delete@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const category = await testPrisma.todoCategory.create({
      data: { userId: user.id, name: '削除対象' },
    })

    await deleteCategory(makeFormData({ id: category.id }))

    const found = await testPrisma.todoCategory.findUnique({ where: { id: category.id } })
    expect(found).toBeNull()
  })

  it("should not delete another user's category (ownership check)", async () => {
    const userA = await createUser('owner-a@example.com')
    const userB = await createUser('owner-b@example.com')

    const categoryA = await testPrisma.todoCategory.create({
      data: { userId: userA.id, name: 'A のカテゴリ' },
    })

    // userB でログイン中に userA のカテゴリ id を渡す
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)

    await deleteCategory(makeFormData({ id: categoryA.id }))

    const found = await testPrisma.todoCategory.findUnique({ where: { id: categoryA.id } })
    expect(found).not.toBeNull()
    expect(found?.userId).toBe(userA.id)
  })

  it('should set categoryId to null on linked todos and keep the todos when deleting a category in use', async () => {
    const user = await createUser('in-use@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const category = await testPrisma.todoCategory.create({
      data: { userId: user.id, name: '使用中カテゴリ' },
    })
    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '紐づくタスク', position: 0, categoryId: category.id },
    })

    await deleteCategory(makeFormData({ id: category.id }))

    const foundCategory = await testPrisma.todoCategory.findUnique({ where: { id: category.id } })
    expect(foundCategory).toBeNull()

    const foundTodo = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(foundTodo).not.toBeNull()
    expect(foundTodo?.categoryId).toBeNull()
  })

  it('should redirect to /login and not change the DB when not logged in', async () => {
    const user = await createUser('delete-guest@example.com')
    const category = await testPrisma.todoCategory.create({
      data: { userId: user.id, name: '未ログイン時は保持' },
    })

    mockGetSession.mockResolvedValue(null)

    await expect(deleteCategory(makeFormData({ id: category.id }))).rejects.toThrow(
      'NEXT_REDIRECT:/login',
    )

    const found = await testPrisma.todoCategory.findUnique({ where: { id: category.id } })
    expect(found).not.toBeNull()
  })
})
