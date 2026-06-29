---
name: linear-walkthrough
description: |
  実装完了後にコードの構造と動作を順序立てて解説するドキュメントを生成する。PRレビュー時の理解促進とComprehension Debt対策。
  TRIGGER when: 「変更内容まとめて」「ウォークスルーして」「実装の解説書いて」など、実装内容の構造解説を求められたとき。
  DO NOT TRIGGER when: PR 作成全体（→ create-pr スキルが内部で呼ぶ）、設計ドキュメント作成（→ design スキル）。
user_invocable: true
command: /walkthrough
argument-hint: "[Issue番号 or ブランチ名]"
---

# Linear Walkthrough 生成

実装完了後のコードを分析し、構造と動作を順序立てて解説するドキュメントを生成する。

## 背景

AI支援開発では生成速度と理解速度のギャップが5-7倍に達する。このComprehension Debt（理解負債）を解消するために、Simon Willisonが提唱したLinear Walkthroughを適用する。

## 出力先

- ドキュメント: `raw/issues/YYYY-MM-DD_<issue番号>/changes.md`

## 生成手順

### 1. 変更ファイルの特定

`git diff $(git merge-base HEAD origin/HEAD)...HEAD --name-only` で変更ファイル一覧を取得し、テストファイル・設定ファイル・ドキュメントを分類する。main 以外のブランチから切った場合にも対応する。

### 2. 概要

何を実装したか、なぜ必要だったかを1-2文で記述する。

### 3. アーキテクチャ概要

変更されたコンポーネント間の関係をテキストで記述する。

### 3.5. Mermaid フローチャート（必須）

変更の処理フローを Mermaid フローチャートで記述する。

処理のステップバイステップの流れを表現し、主要な判断分岐を含める。このフローチャートは PR 本文に転記されるため、レビュアーが処理の全体像を一目で把握できるようにする。

**構文の注意**: GitHub でレンダリングされるため、subgraph タイトルにノード形状記法を使わないこと。詳細は `uml` スキルの「GitHub 互換 Mermaid 構文ルール」を参照。

### 4. エントリーポイント

実行の起点となるファイル・関数を特定し、コードを引用する。

### 5. データフロー

データがシステム内をどう流れるかをテキストで記述する。

### 6. 主要な判断分岐

条件分岐とその理由を列挙する。

### 7. 外部依存

DB, API, ライブラリとの接点を整理する。

### 8. 副作用

書き込み、通知、状態変更を明示する。

### 9. コードウォークスルー

ファイル順にキーコードを引用しながら解説する。

## コード引用ルール

- `grep` / `cat` で実ファイルから抽出する（記憶から書かない）
- ファイルパスと行番号を明記する
- 長いコードは要点のみ抽出し、省略箇所を `// ...` で示す

## PR 連携

- changes.md 内の Mermaid コードブロックを PR 本文の `## Changes` セクションに転記する（GitHub が Mermaid をネイティブレンダリングする）
- changes.md へのリンクを PR 本文に含める

## 他スキルからの呼び出し

- `create-pr`: PR 作成プロセスの最初のステップとして呼び出される
- `implementation-process-gachi`（ガチモード）: Phase C で `/create-pr` 経由で呼び出し
- `implementation-process-nori`（ノリモード）: Phase 4 で `/create-pr` 経由で呼び出し
