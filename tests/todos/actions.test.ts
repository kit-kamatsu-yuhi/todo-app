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

import { createTodo, deleteTodo, updateTodoTitle, toggleTodo, moveTodo } from '@/app/actions/todos'
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

describe('updateTodoTitle', () => {
  it('should update the title of the own todo and return null on success', async () => {
    const user = await createUser('update@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '編集前', position: 0 },
    })

    const result = await updateTodoTitle(
      null,
      makeFormData({ id: todo.id, title: '編集後' }),
    )

    expect(result).toBeNull()

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.title).toBe('編集後')
  })

  it('should return an error and not update the title when title is empty', async () => {
    const user = await createUser('update-empty@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '編集前', position: 0 },
    })

    const result = await updateTodoTitle(null, makeFormData({ id: todo.id, title: '' }))

    expect(result).toEqual({ error: 'タイトルを入力してください' })

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.title).toBe('編集前')
  })

  it('should return an error and not update the title when title is only whitespace', async () => {
    const user = await createUser('update-whitespace@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '編集前', position: 0 },
    })

    const result = await updateTodoTitle(null, makeFormData({ id: todo.id, title: '   ' }))

    expect(result).toEqual({ error: 'タイトルを入力してください' })

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.title).toBe('編集前')
  })

  it('should return a length-specific error when the title exceeds 255 characters', async () => {
    const user = await createUser('update-toolong@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '編集前', position: 0 },
    })

    const result = await updateTodoTitle(
      null,
      makeFormData({ id: todo.id, title: 'あ'.repeat(256) }),
    )

    expect(result).toEqual({ error: 'タイトルは255文字以内で入力してください' })

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.title).toBe('編集前')
  })

  it('should return an error and not update the title when not logged in', async () => {
    const user = await createUser('update-guest@example.com')
    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '編集前', position: 0 },
    })

    mockGetSession.mockResolvedValue(null)

    const result = await updateTodoTitle(
      null,
      makeFormData({ id: todo.id, title: '編集後' }),
    )

    expect(result).toEqual({ error: 'ログインが必要です' })

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.title).toBe('編集前')
  })

  it("should return an error and not update another user's todo (ownership check)", async () => {
    const userA = await createUser('update-owner-a@example.com')
    const userB = await createUser('update-owner-b@example.com')

    const todoA = await testPrisma.todo.create({
      data: { userId: userA.id, title: 'A のタスク', position: 0 },
    })

    // userB でログイン中に userA の todo id を渡す
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)

    const result = await updateTodoTitle(
      null,
      makeFormData({ id: todoA.id, title: '書き換え試行' }),
    )

    expect(result).toEqual({ error: 'TODO が見つかりません' })

    const found = await testPrisma.todo.findUnique({ where: { id: todoA.id } })
    expect(found?.title).toBe('A のタスク')
  })
})

describe('toggleTodo', () => {
  it('should toggle completed from false to true', async () => {
    const user = await createUser('toggle-false-true@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '未完了タスク', position: 0, completed: false },
    })

    await toggleTodo(makeFormData({ id: todo.id }))

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.completed).toBe(true)
  })

  it('should toggle completed from true to false', async () => {
    const user = await createUser('toggle-true-false@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '完了済みタスク', position: 0, completed: true },
    })

    await toggleTodo(makeFormData({ id: todo.id }))

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.completed).toBe(false)
  })

  it("should not change another user's todo (ownership check)", async () => {
    const userA = await createUser('toggle-owner-a@example.com')
    const userB = await createUser('toggle-owner-b@example.com')

    const todoA = await testPrisma.todo.create({
      data: { userId: userA.id, title: 'A のタスク', position: 0, completed: false },
    })

    // userB でログイン中に userA の todo id を渡す
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)

    await toggleTodo(makeFormData({ id: todoA.id }))

    const found = await testPrisma.todo.findUnique({ where: { id: todoA.id } })
    expect(found?.completed).toBe(false)
  })

  it('should redirect to /login and not change the DB when not logged in', async () => {
    const user = await createUser('toggle-guest@example.com')
    const todo = await testPrisma.todo.create({
      data: { userId: user.id, title: '未ログイン時は保持', position: 0, completed: false },
    })

    mockGetSession.mockResolvedValue(null)

    await expect(toggleTodo(makeFormData({ id: todo.id }))).rejects.toThrow(
      'NEXT_REDIRECT:/login',
    )

    const found = await testPrisma.todo.findUnique({ where: { id: todo.id } })
    expect(found?.completed).toBe(false)
  })
})

describe('moveTodo', () => {
  async function createThreeTodos(userId: string) {
    const t0 = await testPrisma.todo.create({
      data: { userId, title: '1件目', position: 0 },
    })
    const t1 = await testPrisma.todo.create({
      data: { userId, title: '2件目', position: 1 },
    })
    const t2 = await testPrisma.todo.create({
      data: { userId, title: '3件目', position: 2 },
    })
    return [t0, t1, t2]
  }

  it('should swap position with the previous todo when moving up', async () => {
    const user = await createUser('move-up@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [t0, t1] = await createThreeTodos(user.id)

    await moveTodo(makeFormData({ id: t1.id, direction: 'up' }))

    const found0 = await testPrisma.todo.findUnique({ where: { id: t0.id } })
    const found1 = await testPrisma.todo.findUnique({ where: { id: t1.id } })
    expect(found1?.position).toBe(0)
    expect(found0?.position).toBe(1)
  })

  it('should swap position with the next todo when moving down', async () => {
    const user = await createUser('move-down@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [, t1, t2] = await createThreeTodos(user.id)

    await moveTodo(makeFormData({ id: t1.id, direction: 'down' }))

    const found1 = await testPrisma.todo.findUnique({ where: { id: t1.id } })
    const found2 = await testPrisma.todo.findUnique({ where: { id: t2.id } })
    expect(found1?.position).toBe(2)
    expect(found2?.position).toBe(1)
  })

  it('should be a no-op when moving the first todo up', async () => {
    const user = await createUser('move-up-first@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [t0] = await createThreeTodos(user.id)

    await moveTodo(makeFormData({ id: t0.id, direction: 'up' }))

    const found0 = await testPrisma.todo.findUnique({ where: { id: t0.id } })
    expect(found0?.position).toBe(0)
  })

  it('should be a no-op when moving the last todo down', async () => {
    const user = await createUser('move-down-last@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [, , t2] = await createThreeTodos(user.id)

    await moveTodo(makeFormData({ id: t2.id, direction: 'down' }))

    const found2 = await testPrisma.todo.findUnique({ where: { id: t2.id } })
    expect(found2?.position).toBe(2)
  })

  it("should not change positions when the id belongs to another user (ownership check)", async () => {
    const userA = await createUser('move-owner-a@example.com')
    const userB = await createUser('move-owner-b@example.com')

    const [t0, t1] = await createThreeTodos(userA.id)

    // userB でログイン中に userA の todo id を渡す（neighbor も不変であること）
    mockGetSession.mockResolvedValue({ userId: userB.id } as never)

    await moveTodo(makeFormData({ id: t1.id, direction: 'up' }))

    const found0 = await testPrisma.todo.findUnique({ where: { id: t0.id } })
    const found1 = await testPrisma.todo.findUnique({ where: { id: t1.id } })
    expect(found0?.position).toBe(0)
    expect(found1?.position).toBe(1)
  })

  it('should redirect to /login and not change the DB when not logged in', async () => {
    const user = await createUser('move-guest@example.com')
    const [t0, t1] = await createThreeTodos(user.id)

    mockGetSession.mockResolvedValue(null)

    await expect(moveTodo(makeFormData({ id: t1.id, direction: 'up' }))).rejects.toThrow(
      'NEXT_REDIRECT:/login',
    )

    const found0 = await testPrisma.todo.findUnique({ where: { id: t0.id } })
    const found1 = await testPrisma.todo.findUnique({ where: { id: t1.id } })
    expect(found0?.position).toBe(0)
    expect(found1?.position).toBe(1)
  })

  it('should keep positions contiguous when the same todo is moved concurrently twice', async () => {
    const user = await createUser('move-concurrent-same@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [, t1] = await createThreeTodos(user.id)

    // 同一 todo に対する同方向の move を同時に発行し、Node.js のイベントループ上での
    // interleaving を再現する。対話的トランザクションであれば片方が no-op になっても
    // position の整合性（連番・重複なし）は保たれるはずである。
    await Promise.all([
      moveTodo(makeFormData({ id: t1.id, direction: 'up' })),
      moveTodo(makeFormData({ id: t1.id, direction: 'up' })),
    ])

    const todos = await testPrisma.todo.findMany({
      where: { userId: user.id },
      orderBy: { position: 'asc' },
    })
    expect(todos.map((t) => t.position)).toEqual([0, 1, 2])
    // 重複や欠番がないことを明示的に確認する
    expect(new Set(todos.map((t) => t.position)).size).toBe(todos.length)
  })

  it('should keep positions contiguous when moving different todos up and down concurrently', async () => {
    const user = await createUser('move-concurrent-diff@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    // position 0,1,2,3 の4件を用意し、隣接ペアが重ならない2組（0↔1, 2↔3）に対して
    // それぞれ独立した move（上移動・下移動）を同時に発行する。
    const [, t1, t2] = await createThreeTodos(user.id)
    await testPrisma.todo.create({
      data: { userId: user.id, title: '4件目', position: 3 },
    })

    await Promise.all([
      moveTodo(makeFormData({ id: t1.id, direction: 'up' })), // 0↔1 ペア
      moveTodo(makeFormData({ id: t2.id, direction: 'down' })), // 2↔3 ペア
    ])

    const todos = await testPrisma.todo.findMany({
      where: { userId: user.id },
      orderBy: { position: 'asc' },
    })
    expect(todos.map((t) => t.position)).toEqual([0, 1, 2, 3])
    expect(new Set(todos.map((t) => t.position)).size).toBe(todos.length)
  })
})
