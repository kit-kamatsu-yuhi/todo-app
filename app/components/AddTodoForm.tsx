'use client'

import { useActionState, useEffect, useRef } from 'react'
import { createTodo } from '@/app/actions/todos'

export default function AddTodoForm() {
  const [state, action, pending] = useActionState(createTodo, null)
  const formRef = useRef<HTMLFormElement>(null)
  // 初回マウント（未送信）と送信成功を区別するためのフラグ。
  // state=null は初期状態と成功の両方で成立するため、これだけでは判別できない。
  const submittedRef = useRef(false)

  useEffect(() => {
    if (pending) {
      submittedRef.current = true
      return
    }
    // 一度送信済みかつ pending 解除・エラー無し = 追加成功なので入力欄をクリアする
    if (submittedRef.current && state === null) {
      formRef.current?.reset()
    }
  }, [pending, state])

  return (
    <form action={action} ref={formRef}>
      <label htmlFor="title">タイトル</label>
      <input id="title" name="title" type="text" required autoComplete="off" />
      {state?.error && <p role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>追加</button>
    </form>
  )
}
