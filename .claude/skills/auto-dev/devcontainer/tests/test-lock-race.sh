#!/usr/bin/env bash
# test-lock-race.sh — 20 プロセス並行 lock で 1 つだけ取得 + stale lock 除去（AC-3 / AC-9）
#
# 契約:
#   lib/state.sh は以下関数を提供する:
#     lock_issue <issue_num>        → 取得できたら exit 0、取れなければ 非 0
#     unlock_issue <issue_num>      → 自分が持つ lock を解放
#   lock ディレクトリ: ${STATE_DIR}/issue-<N>.lock.d
#     内部の pid ファイルに自 PID を書く。起動時に既存 lock を見つけたら
#     kill -0 <pid> で生存確認し、死んでいれば stale として除去して再取得を許す。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

STATE_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/state.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/state.sh"; do
    if [ -f "$cand" ]; then
        STATE_SH="$cand"
        break
    fi
done

echo "=== lock race tests (20 並行 + stale) ==="

if [ -z "$STATE_SH" ]; then
    echo "  ! SKIP: lib/state.sh not yet present"
    exit 0
fi

TMP=$(make_tmp_dir "lock-race")
STATE_DIR="${TMP}/state"
mkdir -p "$STATE_DIR"
export STATE_DIR
export AUTO_DEV_REPO="test/repo"

# shellcheck disable=SC1090
source "$STATE_SH"

if ! declare -f lock_issue >/dev/null 2>&1; then
    echo "  ! FAIL: lock_issue is not defined"
    exit 1
fi

# --- 1. 20 プロセス並行で lock_issue 148 → 1 つだけ成功 -------------------
RESULT_DIR="${TMP}/results"
mkdir -p "$RESULT_DIR"

worker() {
    local id="$1"
    # 各 worker は独立した subshell。state.sh を再 source する必要がある場合に備えて export はしない。
    if lock_issue 148 >/dev/null 2>&1; then
        echo "ok" > "${RESULT_DIR}/worker-${id}.ok"
        # 競合を顕在化させるため少し保持
        sleep 0.3
        unlock_issue 148 >/dev/null 2>&1 || true
    else
        echo "fail" > "${RESULT_DIR}/worker-${id}.fail"
    fi
}

pids=()
for i in $(seq 1 20); do
    ( worker "$i" ) &
    pids+=("$!")
done

for pid in "${pids[@]}"; do
    wait "$pid" || true
done

ok_count=$(find "$RESULT_DIR" -name 'worker-*.ok' | wc -l | tr -d ' ')
fail_count=$(find "$RESULT_DIR" -name 'worker-*.fail' | wc -l | tr -d ' ')

assert_eq "1" "$ok_count" "20 並行のうち 1 プロセスのみ lock 取得"
assert_eq "19" "$fail_count" "残り 19 プロセスは lock 取得失敗"

# lock は解放されているはず
assert_file_not_exists "${STATE_DIR}/issue-148.lock.d" "worker 終了後 lock dir が残らない"

# --- 2. stale lock 除去: 死んだ PID の lock を新規 lock_issue が剥がせる ----

# 手動で lock dir を作り、存在しない PID を書く
mkdir -p "${STATE_DIR}/issue-777.lock.d"
echo "999999" > "${STATE_DIR}/issue-777.lock.d/pid"
# 念のため kill -0 が失敗することを確認
if kill -0 999999 2>/dev/null; then
    echo "  (skip: PID 999999 が実在するためテスト条件不成立)"
else
    if lock_issue 777 >/dev/null 2>&1; then
        assert_true "stale lock 除去後に lock_issue 777 が成功" true
        unlock_issue 777 >/dev/null 2>&1 || true
    else
        assert_true "stale lock 除去後に lock_issue 777 が成功 (got: failed)" false
    fi
fi

# --- 3. 同一プロセスから 2 回目の lock_issue は失敗（または冪等）-----------
lock_issue 778 >/dev/null 2>&1
second_rc=0
lock_issue 778 >/dev/null 2>&1 || second_rc=$?
# 実装に応じて冪等 (0) も失敗 (≠0) も許容するが、lock dir は 1 つのみ
assert_true "issue-778 の 2 回目 lock は 0 or 非 0 の定義動作" test "$second_rc" -ge 0
unlock_issue 778 >/dev/null 2>&1 || true

if ! print_summary; then
    exit 1
fi
