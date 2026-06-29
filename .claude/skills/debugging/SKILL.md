---
name: debugging
description: デバッグスキル。バグ調査・障害分析・エラー解決の依頼時に使用する。プロジェクト固有のデバッグ手法とツールを提供する。
---

# デバッグ Skill

プロジェクト固有のデバッグ方針。体系的デバッグフロー（再現→隔離→仮説→検証）は一般手法に従う。

## プロジェクト固有の注意点

- TypeScript: ソースマップが有効か確認する（トランスパイル時のスタックトレース）
- TypeScript: `strict` モード前提で Null check 漏れに注意
- Python: `logger.exception()` でスタックトレースを記録する（`error-handling` rule 参照）
- `git bisect` でバグ混入コミットを特定する（GitHub Flow のため feature ブランチ単位で追跡可能）

## よくあるバグパターン

| パターン | 症状 | 対策 |
|---------|------|------|
| Off-by-one | ループの境界で異常 | 境界値テスト追加 |
| Race condition | 不定期に発生 | 排他制御・アトミック操作 |
| Null reference | 特定条件でクラッシュ | Optional chaining・Null check |
| 型の不一致 | 暗黙の型変換で異常値 | strict モード・型チェック |
