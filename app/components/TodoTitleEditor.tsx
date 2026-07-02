'use client'

import { useActionState, useEffect, useRef, useState } from 'react'
import { updateTodoTitle } from '@/app/actions/todos'

export default function TodoTitleEditor({ id, title }: { id: string; title: string }) {
  const [isEditing, setIsEditing] = useState(false)
  const [state, action, pending] = useActionState(updateTodoTitle, null)
  const formRef = useRef<HTMLFormElement>(null)
  // 初回マウント（未送信）と送信成功を区別するためのフラグ。
  // state=null は初期状態と成功の両方で成立するため、これだけでは判別できない。
  const submittedRef = useRef(false)

  useEffect(() => {
    if (pending) {
      submittedRef.current = true
      return
    }
    // 一度送信済みかつ pending 解除・エラー無し = 更新成功なので表示モードに戻す
    if (submittedRef.current && state === null) {
      submittedRef.current = false
      setIsEditing(false)
    }
  }, [pending, state])

  if (!isEditing) {
    return (
      <span>
        <span>{title}</span>
        <button type="button" onClick={() => setIsEditing(true)}>
          編集
        </button>
      </span>
    )
  }

  return (
    <form action={action} ref={formRef}>
      <input type="hidden" name="id" value={id} />
      <label htmlFor={`title-${id}`}>タイトル</label>
      <input
        id={`title-${id}`}
        name="title"
        type="text"
        defaultValue={title}
        required
        autoFocus
        autoComplete="off"
      />
      {state?.error && <p role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>保存</button>
      <button type="button" onClick={() => setIsEditing(false)}>キャンセル</button>
    </form>
  )
}
