'use server'

import { redirect } from 'next/navigation'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { prisma } from '@/lib/prisma'
import { getSession } from '@/lib/auth/session'

export type CategoryActionResult = { error: string } | null

const NameSchema = z.string().trim().min(1).max(50)

export async function createCategory(
  _: CategoryActionResult,
  formData: FormData,
): Promise<CategoryActionResult> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) {
    return { error: 'ログインが必要です' }
  }

  const parsed = NameSchema.safeParse(formData.get('name'))
  if (!parsed.success) {
    // 上限超過は空入力と原因が異なるためメッセージを出し分ける
    const tooLong = parsed.error.issues.some((i) => i.code === 'too_big')
    return {
      error: tooLong
        ? 'カテゴリ名は50文字以内で入力してください'
        : 'カテゴリ名を入力してください',
    }
  }

  try {
    await prisma.todoCategory.create({
      data: { userId: session.userId, name: parsed.data },
    })
  } catch (e) {
    // name 本文は機密扱いのためログに出さず、userId のみコンテキストに含める
    console.error('[categories] createCategory error', { userId: session.userId }, e)
    return { error: 'サーバーエラーが発生しました。しばらくしてから再試行してください' }
  }

  revalidatePath('/')
  return null
}

export async function deleteCategory(formData: FormData): Promise<void> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) redirect('/login')

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') return

  try {
    // 所有者チェック: id と userId の複合条件で他人のカテゴリには物理的に到達しない
    // 紐づく Todo.categoryId の null 化は DB の FK 制約(onDelete: SetNull)に委ねる
    await prisma.todoCategory.deleteMany({ where: { id, userId: session.userId } })
  } catch (e) {
    console.error('[categories] deleteCategory error', { userId: session.userId, categoryId: id }, e)
    return
  }

  revalidatePath('/')
}
