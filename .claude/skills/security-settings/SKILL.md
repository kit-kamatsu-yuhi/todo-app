---
name: security-settings
description: セキュリティ設定のプリセット切り替え。厳格/標準/緩和の3モードで settings.json のセキュリティ項目を一括変更する。
  TRIGGER when: 「セキュリティ設定」「セキュリティ切り替え」「セキュリティゆるめて」「セキュリティ厳しくして」「制限ゆるめて」「ロックダウン」「deny ルール変えたい」「settings のセキュリティ」など、セキュリティ設定の変更・確認に関する発話。
  DO NOT TRIGGER when: コードのセキュリティレビュー、脆弱性スキャン、セキュアコーディングの相談（→ security / security-audit スキルを使う）。
argument-hint: "[プリセット名 or 自然言語（例: 厳しくして / ゆるめて / 今どうなってる？）]"
---

# セキュリティ設定プリセット

Qiita 記事「Claude Code セキュリティ設定10項目」に基づき、セキュリティ設定を**プリセット**で一括切り替えする。

## セキュリティ設定10項目

| # | 設定項目 | 制御方式 |
|---|---------|---------|
| ① | サンドボックス有効化 | settings.json |
| ② | サンドボックス脱出口の塞止 | settings.json（allowUnsandboxedCommands） |
| ③ | 危険コマンドの deny ルール | settings.json（permissions.deny） |
| ④ | 機密ファイルアクセス拒否 | settings.json + PreToolUse hooks |
| ⑤ | ネットワークアクセス制限 | settings.json（network.allowlist） |
| ⑥ | bypassPermissions モード無効化 | settings.json |
| ⑦ | PreToolUse フック | settings.json hooks |
| ⑧ | 権限定期監査 | SessionStart hook（audit-permissions.sh） |
| ⑨ | devcontainer 隔離環境 | 案内のみ |
| ⑩ | Managed Settings（組織管理） | 案内のみ |

## 手順

### 1. 現在の状態を読み取る

`.claude/settings.json` を読み込み、以下を確認する:

- `permissions.deny` のルール数とカテゴリ別内訳
- sandbox の有効/無効
- `allowUnsandboxedCommands` の設定
- `bypassPermissions` の設定
- ネットワーク制限の有無（`network.allowlist`）
- PreToolUse hooks の有無と数

### 2. 現在の状態を表示する

以下のフォーマットで表示する:

```
## 現在のセキュリティ設定

| # | 設定項目 | 状態 |
|---|---------|------|
| ① | サンドボックス | ✅ 有効 / ❌ 無効 |
| ② | 脱出口封鎖 | ✅ 封鎖 / ⚠️ 未設定 |
| ③ | deny ルール | ✅ N件 / ⚠️ 少ない |
| ④ | 機密ファイル保護 | ✅ hooks有効 / ❌ 未設定 |
| ⑤ | ネットワーク制限 | ✅ ホワイトリスト / ⚠️ 制限なし |
| ⑥ | bypassPermissions | ✅ 無効 / ❌ 有効 |
| ⑦ | PreToolUse フック | ✅ N件 / ❌ 未設定 |
| ⑧ | 権限監査 | ✅ hook有効 / ⚠️ 未設定 |
```

### 3. プリセットの選択

`$ARGUMENTS` を以下のルールでプリセットに解決する:

#### プリセット名の直接指定
`strict`, `standard`, `relaxed`（または日本語の `厳格`, `標準`, `緩和`）が含まれていればそのまま使用する。

#### 自然言語からの意図推定

| 意図 | トリガーとなる表現例 | → プリセット |
|------|-------------------|-------------|
| 締める | 「厳しくして」「ロックダウン」「堅くして」「セキュリティ上げて」「本番用にして」 | strict |
| 戻す | 「標準に戻して」「デフォルトにして」「普通にして」「リセット」 | standard |
| 緩める | 「ゆるめて」「制限外して」「自由にして」「開発しやすくして」「邪魔しないで」 | relaxed |
| 確認 | 「今どうなってる？」「状態見せて」「チェックして」（または引数なし） | 状態表示のみ |

上記に当てはまらない曖昧な表現の場合は、3つのプリセットを提示して選択させる:

- **厳格（strict）**: 全設定を最大限に有効化。ネットワークはホワイトリスト方式
- **標準（standard）**: バランスの取れた設定。現在のデフォルトに近い
- **緩和（relaxed）**: 最小限の制限。信頼された環境での開発向け

### 4. プリセットの適用

`.claude/skills/security-settings/references/presets.json` を読み込み、選択されたプリセットの設定値を `.claude/settings.json` に適用する。

**適用ルール:**
- `permissions.deny` はプリセットの値で**置き換え**る（マージではない）
- `hooks` セクションは**変更しない**（既存の hooks を維持する）
- `env`, `enabledPlugins` など無関係のセクションは**変更しない**

### 5. 適用結果の確認

変更後の状態を再度表示し、差分をハイライトする。

### 6. 追加案内（⑨⑩）

適用後に以下を案内する:

#### ⑨ devcontainer 隔離環境

> より強固な隔離が必要な場合は、devcontainer の使用を推奨します:
> - `.devcontainer/devcontainer.json` を作成し、Claude Code を隔離環境で実行
> - ホストのファイルシステムへのアクセスを制限
> - ネットワークの分離も可能

#### ⑩ Managed Settings（組織管理）

> チームで統一したセキュリティポリシーを適用する場合:
> - `/etc/claude/settings.json`（Linux/macOS）にポリシーを配置
> - 個人の settings.json より優先される
> - deny ルールは組織設定と個人設定がマージされる

## 注意事項

- settings.json の変更はセッション再起動後に反映される
- hooks の追加・削除はこのスキルでは行わない（既存を維持）
- プリセット適用前に現在の settings.json のバックアップを取ること
