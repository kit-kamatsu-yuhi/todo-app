# タスクリスト（Issue #11: TODO 編集・並び替え機能）

## 実装タスク
- [x] T1: `app/actions/todos.ts` に `updateTodoTitle` を追加（見積: 1h）
- [x] T2: `app/actions/todos.ts` に `toggleTodo` を追加（見積: 0.5h）
- [x] T3: `app/actions/todos.ts` に `moveTodo`（position swap, トランザクション）を追加（見積: 1.5h）
- [x] T4: `app/components/TodoTitleEditor.tsx` を新規作成（見積: 1h、依存: T1）
- [x] T5: `app/components/TodoList.tsx` を更新（toggle/move フォーム追加、TodoTitleEditor 組み込み、先頭/末尾 disabled 制御）（見積: 1h、依存: T2, T3, T4）

## テストタスク
- [x] T6: `updateTodoTitle` の Unit テスト（成功/空タイトル/空白/255文字超/未ログイン/他人の TODO）（見積: 1h、依存: T1）
- [x] T7: `toggleTodo` の Unit テスト（反転/永続化/他人の TODO は no-op/未ログイン redirect）（見積: 0.5h、依存: T2）
- [x] T8: `moveTodo` の Unit テスト（上/下移動/先頭・末尾での no-op/他人の TODO は no-op/未ログイン redirect）（見積: 1h、依存: T3）
- [x] T9: `TodoTitleEditor` の Component テスト（表示⇄編集切替/保存成功/エラー表示/キャンセル）（見積: 1h、依存: T4）
- [x] T10: `TodoList` の Component テスト（先頭/末尾の disabled 制御・完了表示分岐）（見積: 0.5h、依存: T5）

## レビュー対応タスク（ラウンド2, review-agent Must 指摘）
- [x] T12: `package.json` の `@vitest/coverage-v8` を完全固定バージョンに修正
- [x] T13: `moveTodo` を対話的トランザクションでアトミック化（read+write を同一 tx 内に統一）
- [x] T14: `Todo` モデルに `@@unique([userId, position])` を追加しマイグレーション生成
- [x] T15: `moveTodo` の同時実行（Promise.all）を検証する Unit テストを追加

## ドキュメントタスク
- [ ] T11: `raw/` に Issue #11 実装コンテキストを記録する（`/create-pr` フェーズで `changes.md` として生成）
