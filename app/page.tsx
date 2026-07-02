import { redirect } from 'next/navigation'
import { prisma } from '@/lib/prisma'
import { getSession } from '@/lib/auth/session'
import { logout } from '@/app/actions/auth'
import AddCategoryForm from '@/app/components/AddCategoryForm'
import AddTodoForm from '@/app/components/AddTodoForm'
import CategoryList from '@/app/components/CategoryList'
import TodoList from '@/app/components/TodoList'

export default async function Home({
  searchParams,
}: {
  searchParams?: Promise<{ category?: string }>
}) {
  const session = await getSession()
  if (!session) redirect('/login')

  const params = await searchParams
  const [todos, categories] = await Promise.all([
    prisma.todo.findMany({
      where: {
        userId: session.userId,
        ...(params?.category ? { categoryId: params.category } : {}),
      },
      orderBy: { position: 'asc' },
    }),
    prisma.todoCategory.findMany({
      where: { userId: session.userId },
      orderBy: { createdAt: 'asc' },
    }),
  ])

  return (
    <main>
      <h1>todo-app</h1>
      <AddTodoForm />
      <AddCategoryForm />
      <CategoryList categories={categories} currentCategoryId={params?.category} />
      <TodoList todos={todos} categories={categories} />
      <form action={logout}>
        <button type="submit">ログアウト</button>
      </form>
    </main>
  )
}
