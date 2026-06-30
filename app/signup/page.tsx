'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { signup } from '@/app/actions/auth'

export default function SignupPage() {
  const [state, action, pending] = useActionState(signup, null)

  return (
    <main>
      <h1>新規登録</h1>
      <form action={action}>
        <div>
          <label htmlFor="email">メールアドレス</label>
          <input id="email" name="email" type="email" required autoComplete="email" />
        </div>
        <div>
          <label htmlFor="password">パスワード（8文字以上）</label>
          <input id="password" name="password" type="password" required minLength={8} autoComplete="new-password" />
        </div>
        {state?.error && <p role="alert">{state.error}</p>}
        <button type="submit" disabled={pending}>登録する</button>
      </form>
      <p>
        アカウントをお持ちの方は <Link href="/login">ログイン</Link>
      </p>
    </main>
  )
}
