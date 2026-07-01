import { redirect } from 'next/navigation'
import { prisma } from '@/lib/prisma'
import { getSession } from '@/lib/auth/session'
import { logout } from '@/app/actions/auth'
import AddTodoForm from '@/app/components/AddTodoForm'
import TodoList from '@/app/components/TodoList'

export default async function Home() {
  const session = await getSession()
  if (!session) redirect('/login')

  const todos = await prisma.todo.findMany({
    where: { userId: session.userId },
    orderBy: { position: 'asc' },
  })

  return (
    <main>
      <h1>todo-app</h1>
      <AddTodoForm />
      <TodoList todos={todos} />
      <form action={logout}>
        <button type="submit">ログアウト</button>
      </form>
    </main>
  )
}
