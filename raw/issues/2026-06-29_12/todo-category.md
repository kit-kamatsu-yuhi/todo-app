# Issue #12: TODO カテゴリ機能（TodoCategory テーブル）

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/12
- labels: feat, priority:medium, size:M
- 依存: Depends on #8, #10

## 概要
TodoCategory テーブルを追加し、TODO へのカテゴリ割当・解除と絞り込みを実装する。

## スキーマ
- TodoCategory: id, user_id(FK→User), name, created_at
- Todo に category_id(nullable, FK→TodoCategory, ON DELETE SET NULL) を追加

## 要件の要点
- カテゴリ作成/削除、TODOへの割当/解除、カテゴリ絞り込み(HTMX部分更新)、認可
- 使用中カテゴリ削除方針: 紐づく Todo.category_id を NULL（TODO は残す）

## 受け入れ条件
- カテゴリ作成→保存＆選択肢に出る
- 割当→category_id更新＆表示反映
- 絞り込み→該当カテゴリのTODOのみ
- 使用中カテゴリ削除→紐づくTODOのcategory_idがNULL＆TODO残る
- 他人のカテゴリ操作→認可エラー
