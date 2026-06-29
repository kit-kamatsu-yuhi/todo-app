# Issue #8: User / Todo テーブル作成

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/8
- labels: feat, priority:high, size:S
- 依存: Depends on #7（環境構築）

## 概要
認証と TODO 管理の土台となる `User` / `Todo` テーブルを SQLite に作成し、マイグレーションで管理する。

## スキーマ
- User: id, email(unique), password_hash, created_at
- Todo: id, user_id(FK→User), title, completed(default false), position, created_at, updated_at
- FK 有効化: `PRAGMA foreign_keys=ON`

## 受け入れ条件
- マイグレーション実行で User/Todo が定義通り生成される
- 不正な user_id の Todo 挿入は FK 制約でエラー
- email 重複は unique 制約でエラー
- completed 未指定は default(false)

## 設計メモ
- migrations/ に連番 or タイムスタンプ命名で配置
- User 1-n Todo、completed は integer 0/1、position は同一ユーザー内の並び順
