import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { render, screen, fireEvent, waitFor, cleanup } from '@testing-library/react'

// Server Action をモックする（外部依存のみモック対象とする方針）。
vi.mock('@/app/actions/categories', () => ({ createCategory: vi.fn() }))

import AddCategoryForm from '@/app/components/AddCategoryForm'
import { createCategory } from '@/app/actions/categories'

const mockCreateCategory = vi.mocked(createCategory)

beforeEach(() => {
  vi.clearAllMocks()
})

afterEach(() => {
  cleanup()
})

describe('AddCategoryForm', () => {
  it('should render a text input and the add button', () => {
    render(<AddCategoryForm />)

    expect(screen.getByRole('textbox', { name: 'カテゴリ名' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '追加' })).toBeInTheDocument()
  })

  it('should display the error message returned by the action', async () => {
    mockCreateCategory.mockResolvedValue({ error: 'カテゴリ名を入力してください' })

    render(<AddCategoryForm />)

    const input = screen.getByRole('textbox', { name: 'カテゴリ名' })
    fireEvent.change(input, { target: { value: 'テスト' } })

    // React 19 の form action は submit イベントで発火する
    fireEvent.submit(input.closest('form')!)

    // useActionState はフォーム action 実行後に state を更新するため findBy で待つ
    await waitFor(() => {
      expect(mockCreateCategory).toHaveBeenCalled()
    })
    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('カテゴリ名を入力してください')
  })

  it('should clear the input after a successful submission', async () => {
    mockCreateCategory.mockResolvedValue(null)

    render(<AddCategoryForm />)

    const input = screen.getByRole('textbox', { name: 'カテゴリ名' }) as HTMLInputElement
    fireEvent.change(input, { target: { value: '仕事' } })
    expect(input.value).toBe('仕事')

    fireEvent.submit(input.closest('form')!)

    await waitFor(() => {
      expect(mockCreateCategory).toHaveBeenCalled()
    })
    // 成功（action が null を返す）後、入力欄がリセットされる
    await waitFor(() => {
      expect(input.value).toBe('')
    })
  })
})
