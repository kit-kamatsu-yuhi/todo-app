import { logout } from '@/app/actions/auth'

export default function Home() {
  return (
    <main>
      <h1>todo-app</h1>
      <p>環境構築が完了しました。</p>
      <form action={logout}>
        <button type="submit">ログアウト</button>
      </form>
    </main>
  )
}
