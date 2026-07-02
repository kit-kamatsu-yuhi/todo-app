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

export async function updateTodoTitle(
  _: TodoActionResult,
  formData: FormData,
): Promise<TodoActionResult> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) {
    return { error: 'ログインが必要です' }
  }

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') {
    return { error: 'TODO が見つかりません' }
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
    // 所有者チェック: id と userId の複合条件で他人の TODO には物理的に到達しない
    const result = await prisma.todo.updateMany({
      where: { id, userId: session.userId },
      data: { title: parsed.data },
    })
    if (result.count === 0) {
      return { error: 'TODO が見つかりません' }
    }
  } catch (e) {
    // title 本文は機密扱いのためログに出さず、userId と todoId のみコンテキストに含める
    console.error('[todos] updateTodoTitle error', { userId: session.userId, todoId: id }, e)
    return { error: 'サーバーエラーが発生しました。しばらくしてから再試行してください' }
  }

  revalidatePath('/')
  return null
}

export async function toggleTodo(formData: FormData): Promise<void> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) redirect('/login')

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') return

  try {
    // 所有者チェックを兼ねて現在の todo を取得する。他人の TODO は no-op。
    const todo = await prisma.todo.findFirst({ where: { id, userId: session.userId } })
    if (!todo) return

    await prisma.todo.update({
      where: { id: todo.id },
      data: { completed: !todo.completed },
    })
  } catch (e) {
    console.error('[todos] toggleTodo error', { userId: session.userId, todoId: id }, e)
    return
  }

  revalidatePath('/')
}

const DirectionSchema = z.enum(['up', 'down'])

export async function moveTodo(formData: FormData): Promise<void> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) redirect('/login')

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') return

  const parsedDirection = DirectionSchema.safeParse(formData.get('direction'))
  if (!parsedDirection.success) return
  const direction = parsedDirection.data

  try {
    // 読み取りから書き込みまでを同一トランザクション内で行い、二重クリック等の
    // 同時実行による position の読み取り不整合（read-then-write の競合）を防ぐ。
    await prisma.$transaction(async (tx) => {
      // 所有者チェックを兼ねて現在の todo を取得する。他人の TODO は no-op。
      const current = await tx.todo.findFirst({ where: { id, userId: session.userId } })
      if (!current) return

      const neighborPosition = direction === 'up' ? current.position - 1 : current.position + 1
      const neighbor = await tx.todo.findFirst({
        where: { userId: session.userId, position: neighborPosition },
      })
      // 先頭で上移動 / 末尾で下移動は隣接 todo が存在しないため no-op
      if (!neighbor) return

      // position を入れ替える。(userId, position) には一意制約があるため、
      // current を一時的にどの todo とも衝突しない値へ退避してから入れ替える。
      const tempPosition = -1
      await tx.todo.update({ where: { id: current.id }, data: { position: tempPosition } })
      await tx.todo.update({ where: { id: neighbor.id }, data: { position: current.position } })
      await tx.todo.update({ where: { id: current.id }, data: { position: neighbor.position } })
    })
  } catch (e) {
    console.error('[todos] moveTodo error', { userId: session.userId, todoId: id }, e)
    return
  }

  revalidatePath('/')
}

export async function assignCategory(formData: FormData): Promise<void> {
  // 多層防御: middleware に依存せず Action 内でも認証を再検証する
  const session = await getSession()
  if (!session) redirect('/login')

  const id = formData.get('id')
  if (typeof id !== 'string' || id === '') return

  const rawCategoryId = formData.get('categoryId')
  if (typeof rawCategoryId !== 'string') return

  try {
    await prisma.$transaction(async (tx) => {
      if (rawCategoryId !== '') {
        // 所有権確認: 他人のカテゴリへの参照を防ぐ
        const category = await tx.todoCategory.findFirst({
          where: { id: rawCategoryId, userId: session.userId },
        })
        if (!category) return
      }

      // 所有者チェック: id と userId の複合条件で他人の TODO には物理的に到達しない
      await tx.todo.updateMany({
        where: { id, userId: session.userId },
        data: { categoryId: rawCategoryId || null },
      })
    })
  } catch (e) {
    console.error('[todos] assignCategory error', { userId: session.userId, todoId: id }, e)
    return
  }

  revalidatePath('/')
}
