import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'

// next/navigation の redirect をモック（未ログイン分岐で throw させて捕捉できるようにする）。
vi.mock('next/navigation', () => ({
  redirect: vi.fn().mockImplementation((url: string) => {
    throw new Error(`NEXT_REDIRECT:${url}`)
  }),
}))

// getSession をモックしてログイン済みユーザーを返す。
vi.mock('@/lib/auth/session', () => ({ getSession: vi.fn() }))

// prisma.todo.findMany をモックする（一覧取得は DB 依存の外部境界）。
vi.mock('@/lib/prisma', () => ({
  prisma: { todo: { findMany: vi.fn() } },
}))

import Home from '@/app/page'
import { getSession } from '@/lib/auth/session'
import { prisma } from '@/lib/prisma'

const mockGetSession = vi.mocked(getSession)
const mockFindMany = vi.mocked(prisma.todo.findMany)

const now = new Date()

beforeEach(() => {
  vi.clearAllMocks()
  mockGetSession.mockResolvedValue({
    userId: 'u1',
    user: { id: 'u1', email: 'user@example.com' },
  } as never)
  mockFindMany.mockResolvedValue([
    {
      id: 't1',
      userId: 'u1',
      title: 'サンプルTODO',
      completed: false,
      position: 0,
      createdAt: now,
      updatedAt: now,
    },
  ] as never)
})

afterEach(() => {
  cleanup()
})

describe('トップページ', () => {
  it('「todo-app」見出しを表示する', async () => {
    const ui = await Home()
    render(ui)

    expect(
      screen.getByRole('heading', { name: 'todo-app', level: 1 }),
    ).toBeInTheDocument()
  })

  it('ログインユーザーの TODO 一覧を表示する', async () => {
    const ui = await Home()
    render(ui)

    expect(screen.getByText('サンプルTODO')).toBeInTheDocument()
  })
})
