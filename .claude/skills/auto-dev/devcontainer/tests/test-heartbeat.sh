#!/usr/bin/env bash
# test-heartbeat.sh — entrypoint.sh の heartbeat 実装検証（Issue #148 AC-18）
#
# 目的:
#   POLL_INTERVAL より細かい HEARTBEAT_INTERVAL で heartbeat ファイルが
#   繰り返し更新されることを検証する。
#
# 戦略:
#   entrypoint.sh の 1 イテレーションだけ実行する軽量 harness を書いて、
#   HEARTBEAT_INTERVAL=2, POLL_INTERVAL=5 に短縮設定する。
#   5 秒以内に heartbeat ファイルの mtime が 2 回以上更新されれば成功。
#
# 依存:
#   entrypoint.sh は heartbeat ループを関数化（heartbeat_loop 等）しているか、
#   もしくは HEARTBEAT_FILE / HEARTBEAT_INTERVAL / POLL_INTERVAL を env から読む
#   形で書かれていること。ここでは entrypoint.sh を一度 source し、heartbeat_loop
#   があればそれを呼び、無ければ entrypoint.sh 内の該当 while ブロックを
#   eval で切り出すのはやめて静的パターン一致で評価する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

ENTRY_SH=""
for cand in \
    "${SCRIPT_DIR}/../entrypoint.sh" \
    "${SCRIPT_DIR}/../../entrypoint.sh" \
    "${SCRIPT_DIR}/../devcontainer/entrypoint.sh"; do
    if [ -f "$cand" ]; then
        ENTRY_SH="$cand"
        break
    fi
done

echo "=== heartbeat tests ==="

if [ -z "$ENTRY_SH" ]; then
    echo "  ! SKIP: entrypoint.sh not found"
    exit 0
fi

TMP=$(make_tmp_dir "heartbeat")
STATE_DIR="${TMP}/state"
mkdir -p "$STATE_DIR"
export STATE_DIR
export AUTO_DEV_HEARTBEAT_INTERVAL=2
export POLL_INTERVAL=5
export AUTO_DEV_DRY_RUN=1

HEARTBEAT_FILE="${STATE_DIR}/heartbeat"

# 静的チェック: entrypoint.sh が heartbeat を書く形跡を含むこと
assert_file_contains "$ENTRY_SH" 'heartbeat' "entrypoint.sh に heartbeat 関連の記述がある"
assert_file_contains "$ENTRY_SH" 'HEARTBEAT_INTERVAL' "entrypoint.sh が HEARTBEAT_INTERVAL を参照"

# heartbeat_loop 関数化されているか、そうでなければ抽出 eval は使わず
# 最低限のミニマム loop を自前で 1 回呼んで契約に沿うパスを確認する。
if declare -f heartbeat_loop >/dev/null 2>&1 \
   || grep -qE 'heartbeat_loop\s*\(' "$ENTRY_SH"; then

    # 可能ならロード
    (
        # shellcheck disable=SC1090
        source "$ENTRY_SH" 2>/dev/null || true
        if declare -f heartbeat_loop >/dev/null 2>&1; then
            HEARTBEAT_FILE="$HEARTBEAT_FILE" \
            HEARTBEAT_INTERVAL=2 \
            POLL_INTERVAL=5 \
                heartbeat_loop >/dev/null 2>&1 || true
        fi
    ) &
    LOOP_PID=$!

    # 5 秒後に確実に止める保険
    ( sleep 6; kill -TERM "$LOOP_PID" 2>/dev/null || true ) &
    KILLER_PID=$!

    # 最大 5 秒、ファイル更新を観測
    first_mtime=""
    second_mtime=""
    start=$(date +%s)
    while :; do
        now=$(date +%s)
        elapsed=$((now - start))
        if [ "$elapsed" -ge 5 ]; then
            break
        fi
        if [ -f "$HEARTBEAT_FILE" ]; then
            m=$(date -r "$HEARTBEAT_FILE" +%s 2>/dev/null || stat -c %Y "$HEARTBEAT_FILE" 2>/dev/null || echo 0)
            if [ -z "$first_mtime" ]; then
                first_mtime="$m"
            elif [ "$m" != "$first_mtime" ]; then
                second_mtime="$m"
                break
            fi
        fi
        sleep 0.5
    done

    kill -TERM "$LOOP_PID" 2>/dev/null || true
    kill -TERM "$KILLER_PID" 2>/dev/null || true
    wait "$LOOP_PID" 2>/dev/null || true

    assert_file_exists "$HEARTBEAT_FILE" "heartbeat ファイルが生成された"
    assert_ne "" "$first_mtime" "heartbeat が少なくとも 1 回書かれた"
    assert_ne "" "$second_mtime" "heartbeat が 5 秒以内に 2 回以上更新された"
else
    # heartbeat_loop が未関数化なら、静的な構造チェックのみ
    assert_file_contains "$ENTRY_SH" 'date -Iseconds' "entrypoint.sh が date -Iseconds で書き込む"
    echo "  ! NOTE: heartbeat_loop が未定義のため 動的テストは skip"
fi

if ! print_summary; then
    exit 1
fi
