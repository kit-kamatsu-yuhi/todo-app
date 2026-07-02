import type { Todo, TodoCategory } from '@prisma/client'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'

// Server Actions をモックする（外部依存のみモック対象とする方針）。
vi.mock('@/app/actions/todos', () => ({
  deleteTodo: vi.fn(),
  toggleTodo: vi.fn(),
  moveTodo: vi.fn(),
  assignCategory: vi.fn(),
}))

// TodoTitleEditor は Client Component の別ユニットでテスト済みのため、
// TodoList のテストでは表示内容のみ検証できるよう最小限のスタブに差し替える。
vi.mock('@/app/components/TodoTitleEditor', () => ({
  default: ({ title }: { id: string; title: string }) => <span>{title}</span>,
}))

import TodoList from '@/app/components/TodoList'

afterEach(() => {
  cleanup()
})

function makeTodo(overrides: Partial<Todo> = {}): Todo {
  return {
    id: 'todo-1',
    userId: 'user-1',
    title: 'タスク',
    completed: false,
    position: 0,
    createdAt: new Date(),
    updatedAt: new Date(),
    categoryId: null,
    ...overrides,
  }
}

function makeCategory(overrides: Partial<TodoCategory> = {}): TodoCategory {
  return {
    id: 'category-1',
    userId: 'user-1',
    name: 'カテゴリ',
    createdAt: new Date(),
    ...overrides,
  }
}

describe('TodoList', () => {
  it('should disable the up button for the first todo and the down button for the last todo', () => {
    const todos = [
      makeTodo({ id: 'todo-1', title: '1件目', position: 0 }),
      makeTodo({ id: 'todo-2', title: '2件目', position: 1 }),
      makeTodo({ id: 'todo-3', title: '3件目', position: 2 }),
    ]

    render(<TodoList todos={todos} categories={[]} />)

    const upButtons = screen.getAllByRole('button', { name: '▲' })
    const downButtons = screen.getAllByRole('button', { name: '▼' })

    expect(upButtons[0]).toBeDisabled()
    expect(upButtons[1]).not.toBeDisabled()
    expect(upButtons[2]).not.toBeDisabled()

    expect(downButtons[0]).not.toBeDisabled()
    expect(downButtons[1]).not.toBeDisabled()
    expect(downButtons[2]).toBeDisabled()
  })

  it('should render differently for completed and incomplete todos', () => {
    const todos = [
      makeTodo({ id: 'todo-1', title: '未完了タスク', completed: false, position: 0 }),
      makeTodo({ id: 'todo-2', title: '完了済みタスク', completed: true, position: 1 }),
    ]

    render(<TodoList todos={todos} categories={[]} />)

    expect(screen.getByRole('button', { name: '完了' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '未完了に戻す' })).toBeInTheDocument()
  })

  it('should show a message when there are no todos', () => {
    render(<TodoList todos={[]} categories={[]} />)

    expect(screen.getByText('TODO がありません')).toBeInTheDocument()
  })

  it('should render category options and select "未分類" for a todo without a category', () => {
    const todos = [makeTodo({ id: 'todo-1', title: '未分類タスク', categoryId: null })]
    const categories = [
      makeCategory({ id: 'category-1', name: '仕事' }),
      makeCategory({ id: 'category-2', name: '個人' }),
    ]

    render(<TodoList todos={todos} categories={categories} />)

    const select = screen.getByRole('combobox') as HTMLSelectElement
    expect(select.value).toBe('')
    expect(screen.getByRole('option', { name: '未分類' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: '仕事' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: '個人' })).toBeInTheDocument()
  })

  it('should select the assigned category for a todo that already has one', () => {
    const category = makeCategory({ id: 'category-1', name: '仕事' })
    const todos = [
      makeTodo({ id: 'todo-1', title: '割当済みタスク', categoryId: category.id }),
    ]

    render(<TodoList todos={todos} categories={[category]} />)

    const select = screen.getByRole('combobox') as HTMLSelectElement
    expect(select.value).toBe(category.id)
  })

  it('should render without errors when categories is an empty array', () => {
    const todos = [makeTodo({ id: 'todo-1', title: 'カテゴリなしタスク' })]

    render(<TodoList todos={todos} categories={[]} />)

    expect(screen.getByText('カテゴリなしタスク')).toBeInTheDocument()
    expect(screen.getByRole('option', { name: '未分類' })).toBeInTheDocument()
  })
})
