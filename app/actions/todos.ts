'use server'

import { redirect } from 'next/navigation'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { prisma } from '@/lib/prisma'
import { getSession } from '@/lib/auth/session'

export type TodoActionResult = { error: string } | null

const TitleSchema = z.string().trim().min(1).max(255)

export async function createTodo(_: TodoActionResult, formData: FormData): Promise<TodoActionResult> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) {
    return { error: 'ログインが必要です' }
  }

  const parsed = TitleSchema.safeParse(formData.get('title'))
  if (!parsed.success) {
    // 上限超過は空入力と原因が異なるためメッセージを出し分ける
    const tooLong = parsed.error.issues.some((i) => i.code === 'too_big')
    return {
      error: tooLong
        ? 'タイトルは255文字以内で入力してください'
        : 'タイトルを入力してください',
    }
  }

  try {
    // 末尾に追加するため既存の最大 position + 1 を採番する（初回は 0）
    const agg = await prisma.todo.aggregate({
      where: { userId: session.userId },
      _max: { position: true },
    })
    const position = (agg._max.position ?? -1) + 1

    await prisma.todo.create({
      data: { userId: session.userId, title: parsed.data, position },
    })
  } catch (e) {
    // title 本文は機密扱いのためログに出さず、userId のみコンテキストに含める
    console.error('[todos] createTodo error', { userId: session.userId }, e)
    return { error: 'サーバーエラーが発生しました。しばらくしてから再試行してください' }
  }

  revalidatePath('/')
  return null
}

export async function deleteTodo(formData: FormData): Promise<void> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) redirect('/login')

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') return

  try {
    // 所有者チェック: id と userId の複合条件で他人の TODO には物理的に到達しない
    await prisma.todo.deleteMany({ where: { id, userId: session.userId } })
  } catch (e) {
    console.error('[todos] deleteTodo error', { userId: session.userId, todoId: id }, e)
    return
  }

  revalidatePath('/')
}
