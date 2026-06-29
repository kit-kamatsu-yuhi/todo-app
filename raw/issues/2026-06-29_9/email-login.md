# Issue #9: メールアドレスログイン（ログアウト含む）

- date: 2026-06-29
- url: https://github.com/kit-kamatsu-yuhi/todo-app/issues/9
- labels: feat, priority:high, size:M
- 依存: Depends on #7, #8

## 概要
email + password でサインアップ / ログイン / ログアウトを実装し、TODO 操作をログインユーザーに紐づける土台を作る。

## 要件の要点
- password はハッシュ化保存、Cookie セッション(HttpOnly, SameSite)
- 未ログインは保護ページからログインへ誘導、認証ミドルウェアでガード
- HTMX フォーム送信、エラーは部分更新表示

## 受け入れ条件
- サインアップで作成＆ログイン状態
- 正しい資格でログイン→保護ページ可
- 誤 password はエラー部分更新でログイン不可
- ログアウトでセッション無効化、保護ページ不可
- 未ログインの保護ページアクセスはログインへ誘導

## 設計メモ
- 画面 /signup /login + ログアウト、セッションIDをCookie保持（サーバ側保持先は実装選択）
- セキュリティ: 平文保存/ログ禁止、本番 Secure Cookie 想定
