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
// createTodo / deleteTodo が呼ぶため、未モックだとテスト環境でエラーになる。
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))

// lib/auth/session の getSession をモックしてログインユーザーを制御する。
vi.mock('@/lib/auth/session', () => ({ getSession: vi.fn() }))

// lib/prisma をテスト用 DB に差し替える。
vi.mock('@/lib/prisma', () => ({ prisma: testPrisma }))

import { createTodo, deleteTodo } from '@/app/actions/todos'
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

describe('createTodo', () => {
  it('should create a todo linked to the user and return null on valid title', async () => {
    const user = await createUser('create@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createTodo(null, makeFormData({ title: '牛乳を買う' }))

    expect(result).toBeNull()

    const todos = await testPrisma.todo.findMany({ where: { userId: user.id } })
    expect(todos).toHaveLength(1)
    expect(todos[0]).toMatchObject({
      userId: user.id,
      title: '牛乳を買う',
      completed: false,
    })
  })

  it('should return error and not create a todo when title is empty', async () => {
    const user = await createUser('empty@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createTodo(null, makeFormData({ title: '' }))

    expect(result).toEqual({ error: 'タイトルを入力してください' })

    const count = await testPrisma.todo.count()
    expect(count).toBe(0)
  })

  it('should return error and not create a todo when title is only whitespace', async () => {
    const user = await createUser('whitespace@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createTodo(null, makeFormData({ title: '   ' }))

    expect(result).toEqual({ error: 'タイトルを入力してください' })

    const count = await testPrisma.todo.count()
    expect(count).toBe(0)
  })

  it('should return error and not create a todo when not logged in', async () => {
    mockGetSession.mockResolvedValue(null)

    const result = await createTodo(null, makeFormData({ title: '未ログインのタスク' }))

    expect(result).toEqual({ error: 'ログインが必要です' })

    const count = await testPrisma.todo.count()
    expect(count).toBe(0)
  })

  it('should assign incremental positions (0, 1) for consecutive todos', async () => {
    const user = await createUser('position@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    await createTodo(null, makeFormData({ title: '1件目' }))
    await createTodo(null, makeFormData({ title: '2件目' }))

    const todos = await testPrisma.todo.findMany({
      where: { userId: user.id },
      orderBy: { position: 'asc' },
    })
    expect(todos.map((t) => t.position)).toEqual([0, 1])
    expect(todos.map((t) => t.title)).toEqual(['1件目', '2件目'])
  })

  it('should scope position numbering per user', async () => {
    const userA = await createUser('pos-a@example.com')
    const userB = await createUser('pos-b@example.com')

    // userA が position 0,1,2 まで作成する
    mockGetSession.mockResolvedValue({ userId: userA.id } as never)
    await createTodo(null, makeFormData({ title: 'A1' }))
    await createTodo(null, makeFormData({ title: 'A2' }))
    await createTodo(null, makeFormData({ title: 'A3' }))

    // userB の初回追加は userA の position に影響されず 0 になる
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)
    await createTodo(null, makeFormData({ title: 'B1' }))

    const bTodos = await testPrisma.todo.findMany({ where: { userId: userB.id } })
    expect(bTodos).toHaveLength(1)
    expect(bTodos[0].position).toBe(0)
  })

  it('should return a length-specific error when the title exceeds 255 characters', async () => {
    const user = await createUser('toolong@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const result = await createTodo(null, makeFormData({ title: 'あ'.repeat(256) }))

    expect(result).toEqual({ error: 'タイトルは255文字以内で入力してください' })

    const count = await testPrisma.todo.count()
    expect(count).toBe(0)
  })
})

describe('deleteTodo', () => {
  it('should delete own todo from the DB', async () => {
    const user = await createUser('delete@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '削除対象', position: 0 },
    })

    await deleteTodo(makeFormData({ id: todo.id }))

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found).toBeNull()
  })

  it("should not delete another user's todo (ownership check)", async () => {
    const userA = await createUser('owner-a@example.com')
    const userB = await createUser('owner-b@example.com')

    const todoA = await testPrisma.todo.create({
      data: { userId: userA.id, title: 'A のタスク', position: 0 },
    })

    // userB でログイン中に userA の todo id を渡す
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)

    await deleteTodo(makeFormData({ id: todoA.id }))

    const found = await testPrisma.todo.findUnique({ where: { id: todoA.id } })
    expect(found).not.toBeNull()
    expect(found?.userId).toBe(userA.id)
  })

  it("should delete only the owner's todo and leave another user's todo intact", async () => {
    const userA = await createUser('mix-a@example.com')
    const userB = await createUser('mix-b@example.com')

    const todoA = await testPrisma.todo.create({
      data: { userId: userA.id, title: 'A のタスク', position: 0 },
    })
    const todoB = await testPrisma.todo.create({
      data: { userId: userB.id, title: 'B のタスク', position: 0 },
    })

    // userA でログインして自分の todo を削除する
    mockGetSession.mockResolvedValue({ userId: userA.id } as never)
    await deleteTodo(makeFormData({ id: todoA.id }))

    expect(await testPrisma.todo.findUnique({ where: { id: todoA.id } })).toBeNull()
    expect(await testPrisma.todo.findUnique({ where: { id: todoB.id } })).not.toBeNull()
  })

  it('should be a no-op when the id is missing from the form data', async () => {
    const user = await createUser('no-id@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: 'id なしでは消えない', position: 0 },
    })

    await deleteTodo(makeFormData({}))

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found).not.toBeNull()
  })

  it('should redirect to /login and not change the DB when not logged in', async () => {
    const user = await createUser('delete-guest@example.com')
    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '未ログイン時は保持', position: 0 },
    })

    mockGetSession.mockResolvedValue(null)

    await expect(deleteTodo(makeFormData({ id: todo.id }))).rejects.toThrow(
      'NEXT_REDIRECT:/login',
    )

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found).not.toBeNull()
  })
})
