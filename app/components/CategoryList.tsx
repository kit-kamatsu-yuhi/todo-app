import type { TodoCategory } from '@prisma/client'
import { deleteCategory } from '@/app/actions/categories'

export default function CategoryList({
  categories,
  currentCategoryId,
}: {
  categories: TodoCategory[]
  currentCategoryId?: string
}) {
  return (
    <>
      <form method="get">
        <select name="category" defaultValue={currentCategoryId ?? ''}>
          <option value="">すべて</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
        <button type="submit">絞り込む</button>
      </form>
      {categories.length === 0 ? (
        <p>カテゴリがありません</p>
      ) : (
        <ul>
          {categories.map((c) => (
            <li key={c.id}>
              <span>{c.name}</span>
              <form action={deleteCategory}>
                <input type="hidden" name="id" value={c.id} />
                <button type="submit">削除</button>
              </form>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}
