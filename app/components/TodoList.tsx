import type { Todo, TodoCategory } from '@prisma/client'
import { assignCategory, deleteTodo, moveTodo, toggleTodo } from '@/app/actions/todos'
import TodoTitleEditor from '@/app/components/TodoTitleEditor'

export default function TodoList({ todos, categories }: { todos: Todo[]; categories: TodoCategory[] }) {
  if (todos.length === 0) {
    return <p>TODO がありません</p>
  }

  return (
    <ul>
      {todos.map((todo, index) => (
        <li key={todo.id}>
          <form action={toggleTodo}>
            <input type="hidden" name="id" value={todo.id} />
            <button type="submit">{todo.completed ? '未完了に戻す' : '完了'}</button>
          </form>
          <TodoTitleEditor id={todo.id} title={todo.title} />
          <form action={moveTodo}>
            <input type="hidden" name="id" value={todo.id} />
            <input type="hidden" name="direction" value="up" />
            <button type="submit" disabled={index === 0}>▲</button>
          </form>
          <form action={moveTodo}>
            <input type="hidden" name="id" value={todo.id} />
            <input type="hidden" name="direction" value="down" />
            <button type="submit" disabled={index === todos.length - 1}>▼</button>
          </form>
          <form action={assignCategory}>
            <input type="hidden" name="id" value={todo.id} />
            <select name="categoryId" defaultValue={todo.categoryId ?? ''}>
              <option value="">未分類</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
            <button type="submit">変更</button>
          </form>
          <form action={deleteTodo}>
            <input type="hidden" name="id" value={todo.id} />
            <button type="submit">削除</button>
          </form>
        </li>
      ))}
    </ul>
  )
}
