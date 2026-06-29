# Issue #10: TODO 追加・削除機能

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/10
- labels: feat, priority:high, size:M
- 依存: Depends on #8, #9

## 概要
ログインユーザーが自分の TODO を一覧表示・追加・削除できる（最小の縦切り）。

## 要件の要点
- ログインユーザー絞り込みの一覧、追加(空タイトル不可)、削除
- HTMX 部分更新、他ユーザーTODOは操作不可(認可・所有者チェック)

## 受け入れ条件
- 追加→一覧即時反映＆DB保存
- 空タイトルはエラーで保存されない
- 自分のTODO削除→一覧/DBから消える
- 他人のTODO id削除→認可エラー
- 未ログイン操作→ログイン誘導

## 設計メモ
- エンドポイント案: GET /todos, POST /todos, DELETE /todos/:id
- リスト部分テンプレートを返して差し替え
