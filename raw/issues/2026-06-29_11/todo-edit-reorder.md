# Issue #11: TODO 編集・並び替え機能

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/11
- labels: feat, priority:medium, size:M
- 依存: Depends on #10

## 概要
TODO のタイトルのインライン編集、完了/未完了切替の永続化、position による並び替えを実装する。

## 要件の要点
- タイトルインライン編集(空不可)、完了切替の永続化
- 並び替えを position に保存し再読込後も保持、HTMX 部分更新、認可

## 受け入れ条件
- 自分のTODOタイトル編集→表示/DB更新
- 空タイトル編集はエラー
- 完了切替で completed 反転＆再読込後保持
- 並び替えで position 更新＆順序保持
- 他人のTODO編集/並び替えは認可エラー

## 設計メモ
- エンドポイント案: PATCH /todos/:id（タイトル/完了）, POST /todos/reorder（並び順一括）
- 並び替えはドラッグ後に新順序を送信
