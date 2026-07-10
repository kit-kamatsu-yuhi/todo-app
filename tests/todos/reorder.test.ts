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
vi.mock('next/cache', () => ({ revalidatePath: vi.fn() }))

// lib/auth/session の getSession をモックしてログインユーザーを制御する。
vi.mock('@/lib/auth/session', () => ({ getSession: vi.fn() }))

// lib/prisma をテスト用 DB に差し替える。
vi.mock('@/lib/prisma', () => ({ prisma: testPrisma }))

import { moveTodo } from '@/app/actions/todos'
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

async function createTodos(userId: string, titles: string[]) {
  return Promise.all(
    titles.map((title, position) =>
      testPrisma.todo.create({
        data: { userId, title, position },
      }),
    ),
  )
}

async function findTodosByPosition(userId: string) {
  return testPrisma.todo.findMany({
    where: { userId },
    orderBy: { position: 'asc' },
  })
}

function expectContiguousPositions(todos: { position: number }[]) {
  const positions = todos.map((todo) => todo.position)
  expect(positions).toEqual(Array.from({ length: todos.length }, (_, index) => index))
  expect(new Set(positions).size).toBe(todos.length)
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

describe('moveTodo reorder regression (PostgreSQL)', () => {
  it('should swap the last todo toward the first without unique constraint errors', async () => {
    const user = await createUser('reorder-up@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const [first, second, third] = await createTodos(user.id, ['1件目', '2件目', '3件目'])

    await moveTodo(makeFormData({ id: third.id, direction: 'up' }))
    await moveTodo(makeFormData({ id: third.id, direction: 'up' }))

    const todos = await findTodosByPosition(user.id)
    expectContiguousPositions(todos)
    expect(todos.map((todo) => todo.id)).toEqual([third.id, first.id, second.id])
    expect(todos.map((todo) => todo.title)).toEqual(['3件目', '1件目', '2件目'])
  })

  it('should keep positions contiguous while moving one todo from first to last', async () => {
    const user = await createUser('reorder-down@example.com')
    mockGetSession.mockResolvedValue({ userId: user.id } as never)

    const todos = await createTodos(user.id, ['1件目', '2件目', '3件目', '4件目', '5件目'])
    const movingTodo = todos[0]

    for (let step = 0; step < todos.length - 1; step += 1) {
      await moveTodo(makeFormData({ id: movingTodo.id, direction: 'down' }))
      expectContiguousPositions(await findTodosByPosition(user.id))
    }

    const reorderedTodos = await findTodosByPosition(user.id)
    expectContiguousPositions(reorderedTodos)
    expect(reorderedTodos.map((todo) => todo.id)).toEqual([
      ...todos.slice(1).map((todo) => todo.id),
      movingTodo.id,
    ])
  })

  it('should reject direct duplicate positions with P2002', async () => {
    const user = await createUser('reorder-unique@example.com')
    const [first, second] = await createTodos(user.id, ['1件目', '2件目'])

    await expect(
      testPrisma.todo.update({
        where: { id: first.id },
        data: { position: second.position },
      }),
    ).rejects.toMatchObject({ code: 'P2002' })
  })
})
