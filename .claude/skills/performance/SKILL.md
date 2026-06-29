---
name: performance
description: パフォーマンススキル。N+1検出・キャッシュ戦略・負荷テスト・プロファイリングの依頼時に使用する。プロジェクト固有のパフォーマンス方針を提供する。
---

# パフォーマンス Skill

プロジェクト固有のパフォーマンス方針。一般的な最適化知識は省略する。

## パフォーマンス改善の鉄則

1. **推測するな、計測せよ** — ボトルネックは必ず計測で特定する。体感や勘で最適化に着手しない
2. **最も遅い箇所を直す** — アムダールの法則に従い、全体に占める割合が最大の箇所から改善する
3. **仮説→実装→計測→比較** — 改善前後の数値を必ず残す。数値で語れない改善は改善ではない
4. **リグレッション防止** — パフォーマンスバジェットを CI に組み込み、劣化を検知する

## N+1 クエリ検出

### 検出方法

- ORM のクエリログを有効化して確認する
- ループ内で個別にクエリが発行されていないか確認する
- 開発環境でクエリ数をカウントするミドルウェアを導入する

### 対策

| パターン | 対策 |
|---------|------|
| 関連テーブルの逐次取得 | Eager loading（JOIN / preload） |
| 一覧取得後の個別取得 | バッチ取得（WHERE IN） |
| 集計の逐次実行 | サブクエリ / ウィンドウ関数 |

### TypeScript（Prisma）

```typescript
// NG: N+1 — users が 100 件なら 101 回クエリが走る
const users = await prisma.user.findMany();
for (const user of users) {
  const orders = await prisma.order.findMany({ where: { userId: user.id } });
}

// OK: 1 回のクエリで関連データを取得
const users = await prisma.user.findMany({
  include: { orders: true },
});
```

### Python（SQLAlchemy）

```python
# NG: N+1 — user ごとに orders を遅延ロード
users = session.query(User).all()
for user in users:
    print(user.orders)

# OK: JOIN で一括取得
users = session.query(User).options(joinedload(User.orders)).all()
```

### Kotlin（Exposed DAO）

```kotlin
// NG: N+1 — user ごとに orders を遅延ロード
val users = UserEntity.all().toList()
users.forEach { user ->
    println(user.orders.toList()) // 各 user で SELECT が発行される
}

// OK: Eager loading で一括取得
val users = UserEntity.all().with(UserEntity::orders).toList()
users.forEach { user ->
    println(user.orders.toList()) // キャッシュから取得、追加クエリなし
}
```

### Kotlin（Exposed DSL）

```kotlin
// NG: N+1 — ループ内で個別クエリ
val users = Users.selectAll().toList()
users.forEach { user ->
    Orders.selectAll().where { Orders.userId eq user[Users.id] }.toList()
}

// OK: JOIN で一括取得
val result = (Users innerJoin Orders)
    .selectAll()
    .toList()

// OK: サブクエリで一括取得
val orderCounts = Orders
    .select(Orders.userId, Orders.id.count())
    .groupBy(Orders.userId)
```

## キャッシュ戦略

### キャッシュ階層

| 階層 | 手段 | TTL 目安 | 用途 |
|------|------|---------|------|
| ブラウザ | Cache-Control ヘッダー | 静的: 長期 / API: 短期 | 静的アセット、不変データ |
| CDN | Cloudflare / Cloud CDN | 分〜時間 | 静的アセット、公開ページ |
| アプリケーション | Redis / インメモリ | 秒〜分 | セッション、頻繁に参照するデータ |
| DB | クエリキャッシュ / マテビュー | 分〜時間 | 集計結果、マスタデータ |

### キャッシュ無効化

- TTL ベースの自動失効を基本とする
- データ更新時のイベント駆動による明示的な無効化を併用する
- キャッシュキーの命名: `{service}:{entity}:{id}:{version}`

### 注意事項

- キャッシュヒット率を計測する（目標: 80%以上）
- キャッシュスタンピード（TTL 切れで同時に大量リクエストが DB に殺到する）を防止する。ジッター付き TTL やロック機構で対処する
- 個人情報を含むデータのキャッシュは慎重に扱う

## プロファイリング

### CPU プロファイリング

- **TypeScript**: Node.js `--prof` フラグ、clinic.js
- **Python**: cProfile, py-spy（本番環境でも低オーバーヘッド）
- **Kotlin**: VisualVM, async-profiler（本番環境でも低オーバーヘッド）

### メモリプロファイリング

- **TypeScript**: `--inspect` + Chrome DevTools、heapdump
- **Python**: tracemalloc, memory_profiler
- **Kotlin**: VisualVM ヒープダンプ、Eclipse MAT

### Exposed クエリログ

```kotlin
// 開発環境でクエリログを有効化
Database.connect(url, driver) {
    addLogger(StdOutSqlLogger)
}

// クエリ数カウント用カスタムロガー
object QueryCounter : SqlLogger {
    private val count = AtomicInteger(0)
    override fun log(context: StatementContext, transaction: Transaction) {
        count.incrementAndGet()
        println("Query #${count.get()}: ${context.expandArgs(transaction)}")
    }
    fun reset() = count.set(0)
    fun get() = count.get()
}
```

### 確認ポイント

- ホットパス（最も実行時間が長い関数）を特定する
- メモリリーク（ヒープサイズの単調増加）がないか確認する
- GC の頻度と停止時間を確認する

## 負荷テスト

### ツール

- **k6** — JavaScript でシナリオを記述する負荷テストツール（推奨）
- **Locust** — Python でシナリオを記述する負荷テストツール

### テストシナリオ

| テスト種別 | 目的 | 負荷パターン |
|-----------|------|------------|
| Smoke | 基本動作確認 | 最小負荷（1-2 VU） |
| Load | 通常負荷の耐性 | 想定ピークの負荷 |
| Stress | 限界の特定 | 段階的に負荷を増加 |
| Soak | 長時間安定性・メモリリーク検出 | 通常負荷を長時間継続 |

### パフォーマンスバジェット

| 指標 | 目標 |
|------|------|
| API レスポンス時間 p50 | < 200ms |
| API レスポンス時間 p99 | < 1s |
| ページ読み込み時間（LCP） | < 2.5s |
| Time to Interactive（TTI） | < 3.5s |
| バンドルサイズ（JS） | < 200KB（gzip後） |

## フロントエンドパフォーマンス

### 確認ポイント

- 不要な再レンダリングが発生していないか（React DevTools Profiler）
- バンドルサイズが肥大化していないか（webpack-bundle-analyzer / vite-bundle-visualizer）
- 画像の最適化（WebP / AVIF、lazy loading、適切なサイズ指定）
- コード分割（dynamic import）が適切に行われているか

### 対策

| 問題 | 対策 |
|------|------|
| 不要な再レンダリング | React.memo, useMemo, useCallback |
| 長大リスト | 仮想スクロール（react-window, react-virtuoso） |
| 大きなバンドル | コード分割、tree shaking、dynamic import |
| 画像の最適化不足 | next/image、srcset、lazy loading |

## アルゴリズムレベルの最適化

計測でボトルネックが特定されたコードに対して、以下の観点で改善を検討する:

| 観点 | 内容 |
|------|------|
| 計算量 | O(n²) を O(n log n) や O(n) に改善できないか |
| データ構造 | 検索頻度が高ければ配列から Map/Set に変更する |
| 早期リターン | 不要な計算を打ち切る条件を先に評価する |
| バッチ処理 | 1件ずつ処理せず、まとめて処理する |

## ドキュメント出力先

- パフォーマンス計測結果 → `raw/conversations/` に記録
- パフォーマンスバジェット・改善方針 → `wiki/pages/architecture/architecture.md` に反映
