'use server'

import { redirect } from 'next/navigation'
import { z } from 'zod'
import { Prisma } from '@prisma/client'
import { prisma } from '@/lib/prisma'
import { hashPassword, verifyPassword } from '@/lib/auth/password'
import { createSession, deleteSession } from '@/lib/auth/session'

const SignupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
})

export type AuthResult = { error: string } | null

// ユーザーが存在しない場合のタイミング攻撃を防ぐためのダミーハッシュ
// bcrypt.compare は常に実行されるため応答時間が一定になる
const DUMMY_HASH = '$2a$12$LDJRiUkVXkJMdqxzAEYSFuyO/mfPQaZRlW6I6KlRWA0E0HOAo7fE2'

export async function signup(_: AuthResult, formData: FormData): Promise<AuthResult> {
  const parsed = SignupSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  })

  if (!parsed.success) {
    return { error: 'メールアドレスまたはパスワードの形式が正しくありません（パスワードは8文字以上）' }
  }

  const { email, password } = parsed.data

  try {
    const passwordHash = await hashPassword(password)
    const user = await prisma.user.create({ data: { email, passwordHash } })
    await createSession(user.id)
  } catch (e) {
    if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
      return { error: 'このメールアドレスはすでに登録されています' }
    }
    console.error('[auth] signup error', e)
    return { error: 'サーバーエラーが発生しました。しばらくしてから再試行してください' }
  }

  redirect('/')
}

export async function login(_: AuthResult, formData: FormData): Promise<AuthResult> {
  const parsed = LoginSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
  })

  if (!parsed.success) {
    return { error: 'メールアドレスとパスワードを入力してください' }
  }

  const { email, password } = parsed.data

  try {
    const user = await prisma.user.findUnique({ where: { email } })
    const valid = await verifyPassword(password, user?.passwordHash ?? DUMMY_HASH)
    if (!user || !valid) {
      return { error: 'メールアドレスまたはパスワードが正しくありません' }
    }
    await createSession(user.id)
  } catch (e) {
    console.error('[auth] login error', e)
    return { error: 'サーバーエラーが発生しました。しばらくしてから再試行してください' }
  }

  redirect('/')
}

export async function logout(): Promise<void> {
  try {
    await deleteSession()
  } catch (e) {
    console.error('[auth] logout error', e)
  }
  redirect('/login')
}
