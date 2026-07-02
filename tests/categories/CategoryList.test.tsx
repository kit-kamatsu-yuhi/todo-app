import type { TodoCategory } from '@prisma/client'
import { describe, it, expect, afterEach, vi } from 'vitest'
import { render, screen, cleanup } from '@testing-library/react'

// Server Action をモックする（外部依存のみモック対象とする方針）。
vi.mock('@/app/actions/categories', () => ({ deleteCategory: vi.fn() }))

import CategoryList from '@/app/components/CategoryList'

afterEach(() => {
  cleanup()
})

function makeCategory(overrides: Partial<TodoCategory> = {}): TodoCategory {
  return {
    id: 'category-1',
    userId: 'user-1',
    name: 'カテゴリ',
    createdAt: new Date(),
    ...overrides,
  }
}

describe('CategoryList', () => {
  it('should show a message when there are no categories', () => {
    render(<CategoryList categories={[]} />)

    expect(screen.getByText('カテゴリがありません')).toBeInTheDocument()
  })

  it('should render the "すべて" option and each category as a filter option', () => {
    const categories = [
      makeCategory({ id: 'category-1', name: '仕事' }),
      makeCategory({ id: 'category-2', name: '個人' }),
    ]

    render(<CategoryList categories={categories} />)

    expect(screen.getByRole('option', { name: 'すべて' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: '仕事' })).toBeInTheDocument()
    expect(screen.getByRole('option', { name: '個人' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: '絞り込む' })).toBeInTheDocument()
  })

  it('should select "すべて" by default when currentCategoryId is not provided', () => {
    const categories = [makeCategory({ id: 'category-1', name: '仕事' })]

    render(<CategoryList categories={categories} />)

    const select = screen.getByRole('combobox') as HTMLSelectElement
    expect(select.value).toBe('')
  })

  it('should select the matching category when currentCategoryId is provided', () => {
    const categories = [
      makeCategory({ id: 'category-1', name: '仕事' }),
      makeCategory({ id: 'category-2', name: '個人' }),
    ]

    render(<CategoryList categories={categories} currentCategoryId="category-2" />)

    const select = screen.getByRole('combobox') as HTMLSelectElement
    expect(select.value).toBe('category-2')
  })

  it('should render each category name with a delete button', () => {
    const categories = [
      makeCategory({ id: 'category-1', name: '仕事' }),
      makeCategory({ id: 'category-2', name: '個人' }),
    ]

    render(<CategoryList categories={categories} />)

    // カテゴリ名は絞り込みselectのoptionと一覧のspanの両方に現れるため、
    // 一覧側の描画は role で絞って検証する（select 内は getByRole('option') で別途検証済み）。
    const list = screen.getByRole('list')
    expect(list).toHaveTextContent('仕事')
    expect(list).toHaveTextContent('個人')
    expect(screen.getAllByRole('button', { name: '削除' })).toHaveLength(2)
  })
})
