# Example: ログイン → ダッシュボード → ログアウト

## 前提
- `E2E_BASE_URL` が起動可能な Web アプリを指している
- `E2E_LOGIN_EMAIL` / `E2E_LOGIN_PASSWORD` が設定されている

## ステップ
1. `${E2E_BASE_URL}/login` を開く
2. メール入力欄に `${E2E_LOGIN_EMAIL}` を入力
3. パスワード入力欄に `${E2E_LOGIN_PASSWORD}` を入力
4. 「ログイン」ボタンをクリック
5. URL が `**/dashboard` パターンに一致するまで待つ
6. ユーザー名がページに表示されていることを確認
7. 「ログアウト」リンクをクリック
8. URL が `**/login` に戻ることを確認

## Expectations
- ステップ 5 の URL 遷移
- ステップ 6 のユーザー名表示
- ステップ 8 の URL 戻り
