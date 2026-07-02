'use client'

import { useActionState, useEffect, useRef } from 'react'
import { createCategory } from '@/app/actions/categories'

export default function AddCategoryForm() {
  const [state, action, pending] = useActionState(createCategory, null)
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
      <label htmlFor="name">カテゴリ名</label>
      <input id="name" name="name" type="text" required autoComplete="off" />
      {state?.error && <p role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>追加</button>
    </form>
  )
}
