'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { login } from '@/app/actions/auth'

export default function LoginPage() {
  const [state, action, pending] = useActionState(login, null)

  return (
    <main>
      <h1>ログイン</h1>
      <form action={action}>
        <div>
          <label htmlFor="email">メールアドレス</label>
          <input id="email" name="email" type="email" required autoComplete="email" />
        </div>
        <div>
          <label htmlFor="password">パスワード</label>
          <input id="password" name="password" type="password" required autoComplete="current-password" />
        </div>
        {state?.error && <p role="alert">{state.error}</p>}
        <button type="submit" disabled={pending}>ログインする</button>
      </form>
      <p>
        アカウントをお持ちでない方は <Link href="/signup">新規登録</Link>
      </p>
    </main>
  )
}
