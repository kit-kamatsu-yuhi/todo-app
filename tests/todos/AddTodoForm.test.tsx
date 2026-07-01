import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// Server Action をモックする（外部依存のみモック対象とする方針）。
vi.mock('@/app/actions/todos', () => ({ createTodo: vi.fn() }))

import AddTodoForm from '@/app/components/AddTodoForm'
import { createTodo } from '@/app/actions/todos'

const mockCreateTodo = vi.mocked(createTodo)

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  cleanup()
})

describe('AddTodoForm', () => {
  it('should render a text input and the add button', () => {
    render(<AddTodoForm />)

    expect(screen.getByRole('textbox', { name: 'タイトル' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '追加' })).toBeInTheDocument()
  })

  it('should display the error message returned by the action', async () => {
    mockCreateTodo.mockResolvedValue({ error: 'タイトルを入力してください' })

    render(<AddTodoForm />)

    const input = screen.getByRole('textbox', { name: 'タイトル' })
    fireEvent.change(input, { target: { value: 'テスト' } })

    // React 19 の form action は submit イベントで発火する
    fireEvent.submit(input.closest('form')!)

    // useActionState はフォーム action 実行後に state を更新するため findBy で待つ
    await waitFor(() => {
      expect(mockCreateTodo).toHaveBeenCalled()
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('タイトルを入力してください')
  })

  it('should clear the input after a successful submission', async () => {
    mockCreateTodo.mockResolvedValue(null)

    render(<AddTodoForm />)

    const input = screen.getByRole('textbox', { name: 'タイトル' }) as HTMLInputElement
    fireEvent.change(input, { target: { value: '牛乳を買う' } })
    expect(input.value).toBe('牛乳を買う')

    fireEvent.submit(input.closest('form')!)

    await waitFor(() => {
      expect(mockCreateTodo).toHaveBeenCalled()
    })
    // 成功（action が null を返す）後、入力欄がリセットされる
    await waitFor(() => {
      expect(input.value).toBe('')
    })
  })
})
