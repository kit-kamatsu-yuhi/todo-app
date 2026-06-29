---
name: refactoring
description: リファクタリングスキル。安全なリファクタリングパターン・技術的負債管理の依頼時に使用する。プロジェクト固有のリファクタリング方針を提供する。
---

# リファクタリング Skill

プロジェクト固有のリファクタリング方針。リファクタリングの一般概念は省略する。

## リファクタリングプロセス

1. **現状の把握** — 対象コードの動作をテストで保証する
2. **問題の特定** — コードスメルを具体的に言語化する
3. **計画** — 段階的に変更する手順を設計する
4. **実行** — 小さなステップで変更し、各ステップ後にテストを実行する
5. **検証** — リファクタリング前後で動作が変わっていないことを確認する

## 前提条件

- リファクタリング対象のコードに十分なテストが存在すること
- テストが不足している場合は、まずテストを追加してからリファクタリングする
- 機能追加とリファクタリングを同時に行わない（コミットを分ける）

## 可読性の原則

リファクタリングの最大の目的は「他の人が読んで理解できるコード」にすること。

### 名前で意図を伝える

変数名・関数名は「そのコードを読む人が、名前だけで中身を正しく推測できるか」を基準に付ける。

| NG | OK | 理由 |
|-----|-----|------|
| `item` | `orderItem` | 何の item か不明。注文商品であることを名前で伝える |
| `data` | `userProfileResponse` | 何のデータか不明。API レスポンスの中身を名前に含める |
| `list` | `unpaidInvoices` | 何のリストか不明。未払い請求書であることを明示する |
| `tmp` | `formattedAddress` | 一時変数でも中身を表す名前を付ける |
| `d` | `elapsedDays` | 略語を避け、経過日数であることを伝える |
| `flag` | `isEmailVerified` | 何のフラグか不明。メール認証済みかどうかを名前で表現する |
| `val` | `discountRate` | 値の意味を名前に含める |
| `handleClick` | `handleAddToCart` | 何のクリックか不明。カート追加であることを名前で伝える |
| `process` | `calculateShippingFee` | 何を処理するのか不明。送料計算であることを明示する |
| `check` | `validatePaymentMethod` | 何をチェックするのか不明。支払い方法の検証であることを伝える |
| `Manager` | `OrderFulfillmentService` | Manager/Handler/Processor は責務が曖昧。具体的なドメイン操作を名前にする |
| `utils.ts` | `date-formatter.ts` | utils は何でも入る袋。具体的な責務をファイル名にする |

#### スコープと名前の長さ

- スコープが広い変数ほど説明的な名前を付ける
- ループカウンタの `i` や短いラムダの引数はスコープが狭いので許容される
- モジュール公開する関数名は、呼び出し側のコンテキストなしで理解できる名前にする

### 関数の設計

- 関数は 1 つのことだけを行う。名前に「and」「or」が入る関数は分割を検討する
- 抽象度を揃える。高レベルの処理フローの中に低レベルの実装詳細を混ぜない
- 引数は少なく保つ。4 つ以上になったらオブジェクトにまとめる
- 副作用を最小化する。状態を変更する関数と値を返す関数を分離する

```typescript
// NG: 抽象度が混在している
async function processOrder(orderId: string) {
  const order = await db.query(`SELECT * FROM orders WHERE id = $1`, [orderId]);
  if (order.status === "pending") {
    const tax = order.subtotal * 0.1;
    const total = order.subtotal + tax + order.shippingFee;
    await db.query(`UPDATE orders SET total = $1, status = 'confirmed'`, [total]);
    await fetch("https://api.email.com/send", { body: JSON.stringify({ to: order.email }) });
  }
}

// OK: 抽象度が揃っている
async function processOrder(orderId: string) {
  const order = await fetchOrderById(orderId);
  if (!order.isPending()) return;

  const confirmedOrder = order.confirm();
  await saveOrder(confirmedOrder);
  await sendOrderConfirmationEmail(confirmedOrder);
}
```

### コメントの使い方

- コード自体が意図を伝えるのが最善。コメントが必要な時点でコードの改善余地がある
- 「なぜ」を書く。「何をしているか」はコードを読めばわかる
- ハックや回避策には理由を残す。将来の自分や同僚がなぜこう書いたか迷わないように
- TODO / FIXME には Issue 番号を付ける。放置されるコメントにしない

```typescript
// NG: 何をしているかを書いている（コードを読めばわかる）
// ユーザーの年齢を計算する
const userAge = calculateAge(user.birthDate);

// OK: なぜこうしているかを書いている
// 外部決済APIが日本時間で日付を返すため、UTC変換が必要
const paymentDate = convertJstToUtc(rawPaymentDate);
```

### 制御フローの単純化

- ネストを減らす。ガード節（早期リターン）で異常系を先に処理する
- 条件式が複雑なら、意味のある名前の変数に抽出する
- 否定条件（`!isNotReady`）を避ける。肯定形で書き直す
- 三項演算子のネストは避ける。if-else で書く方が読みやすければそうする

```typescript
// NG: ネストが深い
function getShippingLabel(order: Order): string {
  if (order.items.length > 0) {
    if (order.shippingAddress) {
      if (order.isPaid) {
        return generateLabel(order);
      } else {
        throw new Error("未払い");
      }
    } else {
      throw new Error("配送先未設定");
    }
  } else {
    throw new Error("商品なし");
  }
}

// OK: ガード節で早期リターン
function getShippingLabel(order: Order): string {
  if (order.items.length === 0) throw new Error("商品なし");
  if (!order.shippingAddress) throw new Error("配送先未設定");
  if (!order.isPaid) throw new Error("未払い");

  return generateLabel(order);
}
```

### コードの構造化

- 関連するコードを近くに置く。定義と使用箇所が離れていると読みにくい
- 一貫したパターンを使う。同じ種類の処理は同じ書き方をする
- 説明変数を使う。複雑な式の中間結果に名前を付けて読みやすくする

```typescript
// NG: 条件式が複雑で読みにくい
if (user.age >= 18 && user.hasVerifiedEmail && !user.isBanned && user.subscriptionEndDate > new Date()) {
  // ...
}

// OK: 説明変数で意図を明確にする
const isAdult = user.age >= 18;
const isAccountActive = user.hasVerifiedEmail && !user.isBanned;
const hasValidSubscription = user.subscriptionEndDate > new Date();

if (isAdult && isAccountActive && hasValidSubscription) {
  // ...
}
```

## コードスメルと対策

### 構造的な問題

| コードスメル | 兆候 | 対策 |
|------------|------|------|
| 長い関数 | 50行超、複数の責務 | Extract Function |
| 巨大クラス | 多すぎるフィールド・メソッド | Extract Class |
| 長い引数リスト | 4つ以上のパラメータ | Introduce Parameter Object |
| フィーチャーエンビー | 他クラスのデータを頻繁に参照 | Move Method |
| データクランプ | 同じデータ群が複数箇所に出現 | Extract Class / Introduce Parameter Object |

### 変更容易性の問題

| コードスメル | 兆候 | 対策 |
|------------|------|------|
| 散弾銃手術 | 1つの変更が多数のファイルに波及 | Move Method / Inline Class |
| 変更の発散 | 1つのクラスが複数の理由で変更される | Extract Class（単一責任に分離） |
| パラレル継承 | サブクラスを追加するたびに別の階層にもサブクラスが必要 | Move Method / Move Field |

### 不要な複雑さ

| コードスメル | 兆候 | 対策 |
|------------|------|------|
| 投機的汎用性 | 使われていない抽象化・パラメータ | Remove Dead Code / Inline |
| 中間者 | 委譲するだけのクラス・メソッド | Remove Middle Man |
| コメントで説明が必要 | コード自体が意図を伝えていない | Rename / Extract Function |
| マジックナンバー | 意味不明な定数値がコードに散在 | 名前付き定数に置き換える（`0.1` → `TAX_RATE`） |

## 安全なリファクタリング手順

### Rename（名前の変更）

1. IDE のリネーム機能を使う（手動の検索置換は避ける）
2. テストを実行する
3. コンパイル・型チェックを通す

### Extract Function（関数の抽出）

1. 抽出する範囲を特定する
2. 範囲内で使用されている変数を確認する（引数・戻り値になる）
3. 新しい関数を作成し、元の箇所から呼び出す
4. テストを実行する

### Move Method（メソッドの移動）

1. 移動先のクラスに新しいメソッドを作成する
2. 元のメソッドから新しいメソッドを呼び出す（委譲）
3. テストを実行する
4. 呼び出し元を新しいメソッドに切り替える
5. 元のメソッドを削除する
6. テストを実行する

### Replace Conditional with Polymorphism（条件分岐の多態性への置換）

1. 条件分岐の各ケースに対応するサブクラス or ストラテジーを作成する
2. 各サブクラスにメソッドを実装する
3. ファクトリーメソッドで適切なインスタンスを生成する
4. 条件分岐を多態的なメソッド呼び出しに置き換える
5. テストを実行する

## 技術的負債管理

### 負債の分類

| カテゴリ | 説明 | 優先度の判断基準 |
|---------|------|----------------|
| 意図的・短期 | 納期のために意図的に妥協した | 直後のスプリントで返済する |
| 意図的・長期 | トレードオフとして受け入れた | 影響が出始めたら返済する |
| 非意図的 | 知識不足で生まれた負債 | 発見次第、計画に組み込む |

### 負債の記録

技術的負債を発見した場合:

1. GitHub Issue として起票する（`/issue` skill 使用）
2. `tech-debt` ラベルを付与する
3. 影響範囲と返済コストを見積もる
4. 優先度を設定する

### 返済の原則

- 機能開発と並行して少しずつ返済する（ボーイスカウトルール: 触ったコードは来たときより綺麗にして帰る）
- 大規模なリファクタリングは専用の feature ブランチで行う
- リファクタリングの PR は機能変更と分離する

## リファクタリング PR のルール

- PR タイトルに `refactor:` プレフィックスを付ける（Conventional Commits）
- 動作の変更がないことを PR 説明に明記する
- テスト結果（リファクタリング前後で同一であること）を添付する
- 可能な限り小さな単位で PR を作成する

## ドキュメント出力先

- リファクタリング計画 → `raw/issues/` の該当 Issue ディレクトリ
- アーキテクチャへの影響 → `wiki/pages/architecture/architecture.md` に反映
