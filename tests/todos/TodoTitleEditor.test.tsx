import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// Server Action をモックする（外部依存のみモック対象とする方針）。
vi.mock('@/app/actions/todos', () => ({ updateTodoTitle: vi.fn() }))

import TodoTitleEditor from '@/app/components/TodoTitleEditor'
import { updateTodoTitle } from '@/app/actions/todos'

const mockUpdateTodoTitle = vi.mocked(updateTodoTitle)

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  cleanup()
})

describe('TodoTitleEditor', () => {
  it('should render in display mode with the title text and an edit button, without an input', () => {
    render(<TodoTitleEditor id="todo-1" title="牛乳を買う" />)

    expect(screen.getByText('牛乳を買う')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '編集' })).toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })

  it('should switch to edit mode with the title prefilled when the edit button is clicked', () => {
    render(<TodoTitleEditor id="todo-1" title="牛乳を買う" />)

    fireEvent.click(screen.getByRole('button', { name: '編集' }))

    const input = screen.getByRole('textbox') as HTMLInputElement
    expect(input).toBeInTheDocument()
    expect(input.value).toBe('牛乳を買う')
  })

  it('should return to display mode when the save succeeds (action returns null)', async () => {
    mockUpdateTodoTitle.mockResolvedValue(null)

    render(<TodoTitleEditor id="todo-1" title="牛乳を買う" />)

    fireEvent.click(screen.getByRole('button', { name: '編集' }))
    const input = screen.getByRole('textbox') as HTMLInputElement
    fireEvent.change(input, { target: { value: '牛乳とパンを買う' } })
    fireEvent.submit(input.closest('form')!)

    await waitFor(() => {
      expect(mockUpdateTodoTitle).toHaveBeenCalled()
    })
    await waitFor(() => {
      expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    })
    expect(screen.getByRole('button', { name: '編集' })).toBeInTheDocument()
  })

  it('should show the error message and stay in edit mode when the action returns an error', async () => {
    mockUpdateTodoTitle.mockResolvedValue({ error: 'タイトルを入力してください' })

    render(<TodoTitleEditor id="todo-1" title="牛乳を買う" />)

    fireEvent.click(screen.getByRole('button', { name: '編集' }))
    const input = screen.getByRole('textbox') as HTMLInputElement
    fireEvent.change(input, { target: { value: '' } })
    fireEvent.submit(input.closest('form')!)

    await waitFor(() => {
      expect(mockUpdateTodoTitle).toHaveBeenCalled()
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('タイトルを入力してください')
    expect(screen.getByRole('textbox')).toBeInTheDocument()
  })

  it('should discard the input and return to display mode without calling the action when cancel is clicked', () => {
    render(<TodoTitleEditor id="todo-1" title="牛乳を買う" />)

    fireEvent.click(screen.getByRole('button', { name: '編集' }))
    const input = screen.getByRole('textbox') as HTMLInputElement
    fireEvent.change(input, { target: { value: '変更したが保存しない' } })

    fireEvent.click(screen.getByRole('button', { name: 'キャンセル' }))

    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
    expect(screen.getByText('牛乳を買う')).toBeInTheDocument()
    expect(mockUpdateTodoTitle).not.toHaveBeenCalled()
  })
})
