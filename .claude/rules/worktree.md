# Git Worktree 運用（AI 並行作業）

## 方針

ファイルの変更を伴う作業は **git worktree** で行う。メインworktreeでの直接編集を禁止する。複数の AI セッションが同時にファイルを編集しても衝突しないようにする。

## ワークフロー

1. 作業開始時に worktree を作成する
2. worktree 内で feature ブランチを切って編集する
3. 作業完了後に PR を作成する
4. マージ後に worktree を削除する

## Worktree 作成手順

```bash
# worktree を作成（ブランチも同時に作成）
git worktree add .claude/worktrees/<worktree-name> -b feature/<issue番号>-<説明>

# 例
git worktree add .claude/worktrees/42-add-auth -b feature/42-add-auth
```

## ファイル編集時の注意

- Edit / Write ツールでは worktree 内の**絶対パス**を使用する
- 例: `/Users/.../ai-driven-development/.claude/worktrees/42-add-auth/src/index.ts`
- メインworktreeのパスを使わないこと

## Worktree の削除

```bash
# worktree を削除
git worktree remove .claude/worktrees/<worktree-name>

# 古い worktree を一括整理
git worktree prune
```

## パスのルール

worktree 作業中は **すべてのファイル操作を worktree 内の絶対パスで行う**。メインツリーのパスを使ってはならない。

