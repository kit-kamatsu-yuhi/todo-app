import type { Todo } from '@prisma/client'
import { deleteTodo } from '@/app/actions/todos'

export default function TodoList({ todos }: { todos: Todo[] }) {
  if (todos.length === 0) {
    return <p>TODO がありません</p>
  }

  return (
    <ul>
      {todos.map((todo) => (
        <li key={todo.id}>
          <span>{todo.title}</span>
          <form action={deleteTodo}>
            <input type="hidden" name="id" value={todo.id} />
            <button type="submit">削除</button>
          </form>
        </li>
      ))}
    </ul>
  )
}
