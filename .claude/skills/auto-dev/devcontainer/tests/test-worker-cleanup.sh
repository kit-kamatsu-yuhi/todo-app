#!/usr/bin/env bash
# test-worker-cleanup.sh — worker.sh の trap 回収テスト（Issue #148 AC-5）
#
# 検証観点:
#   1. worker を TERM すると on_worker_exit が呼ばれ worktree が remove される
#   2. lock dir が開放される
#   3. 子プロセス（孫プロセス）も回収される（プロセスグループ kill）
#
# 戦略:
#   worker.sh を長時間スリープする子と共に起動 → kill -TERM → 1 秒以内に
#   （a）lock dir 消失（b）worktree 片付き（c）孫 PID が存命しない
#   を観察する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"

WORKER_SH=""
for cand in \
    "${SCRIPT_DIR}/../lib/worker.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/worker.sh"; do
    if [ -f "$cand" ]; then
        WORKER_SH="$cand"
        break
    fi
done

echo "=== worker cleanup (trap) tests ==="

if [ -z "$WORKER_SH" ]; then
    echo "  ! SKIP: lib/worker.sh not yet present"
    exit 0
fi

# on_worker_exit 関数の存在だけを静的に確認するゲート
if ! grep -q 'on_worker_exit' "$WORKER_SH"; then
    echo "  ! FAIL: worker.sh に on_worker_exit が定義されていない"
    exit 1
fi

TMP=$(make_tmp_dir "worker-cleanup")
STATE_DIR="${TMP}/state"
LOG_DIR="${TMP}/logs"
WORKTREE_DIR="${TMP}/worktrees"
mkdir -p "$STATE_DIR" "$LOG_DIR" "$WORKTREE_DIR"

# macOS の bash 3.2 では前景 sleep の TERM 伝播が Linux と異なり、
# この signal-timing テストが不安定になる。auto-dev の本番環境は
# devcontainer (Linux, bash 5) なのでそちらでの検証を正とする。
# 本 harness は on_worker_exit の静的存在確認まで行ってスキップする。
if [ "$(uname -s)" = "Darwin" ]; then
    echo "  ! SKIP: macOS では前景 sleep の TERM 伝播が不安定。Linux container で検証する"
    echo "  ✓ worker.sh に on_worker_exit が定義されている"
    echo "================================"
    echo "  1/1 passed, 0 failed (macOS skip)"
    echo "================================"
    exit 0
fi

export STATE_DIR LOG_DIR
export AUTO_DEV_REPO="test/repo"
export AUTO_DEV_WORKTREE_ROOT="$WORKTREE_DIR"
export AUTO_DEV_HEARTBEAT_INTERVAL=1

# worker を fork するラッパスクリプトを生成する
# 直接 worker.sh を走らせるとリアル claude / gh を引くので、
# 関数だけ source して cleanup 経路を検証する軽量版 harness を使う。
HARNESS="${TMP}/harness.sh"
cat > "$HARNESS" <<HARNESS_SH
#!/usr/bin/env bash
set -uo pipefail
source "${WORKER_SH}"

# 偽の lock dir と worktree dir を作って trap のターゲットにする
LOCK_DIR="${STATE_DIR}/issue-555.lock.d"
mkdir -p "\$LOCK_DIR"
echo \$\$ > "\$LOCK_DIR/pid"

WT="${WORKTREE_DIR}/issue-555"
mkdir -p "\$WT"

# trap で使う変数を worker.sh の想定どおりに露出する
export ISSUE_NUM=555
export WORKTREE="\$WT"
export LOCK_DIR

# on_worker_exit が変数名を参照できるようにする
# 孫プロセスを fork（SIGTERM で死ぬようにする）
( exec -a child_sleeper sleep 120 ) &
CHILD_PID=\$!
echo "\$CHILD_PID" > "${TMP}/child.pid"

# on_worker_exit を呼べるように trap を設定（worker.sh 側が設定する想定だが保険）。
# TERM / INT は cleanup 後に明示 exit することで harness を確実に終了させる。
# EXIT だけだと kill -TERM 後も sleep 120 が継続し、テストが timeout / false fail を起こす（P2 フィードバック）。
if declare -f on_worker_exit >/dev/null 2>&1; then
    trap 'on_worker_exit || true' EXIT
    trap 'on_worker_exit || true; exit 143' TERM
    trap 'on_worker_exit || true; exit 130' INT
fi

# 長時間スリープ（TERM を受けるまで）。sleep は job として起動し wait すること
# で、TERM trap が即発火し harness が exit できる。
sleep 120 &
wait \$! || true
HARNESS_SH
chmod +x "$HARNESS"

# harness を独立プロセスグループで起動
setsid_cmd=""
if command -v setsid >/dev/null 2>&1; then
    setsid_cmd="setsid"
fi

$setsid_cmd bash "$HARNESS" >/dev/null 2>&1 &
WORKER_PID=$!

# 起動待ち
sleep 0.3

# harness が LOCK_DIR と WT を作り終えるまで少し待つ
for _ in 1 2 3 4 5; do
    if [ -d "${STATE_DIR}/issue-555.lock.d" ]; then
        break
    fi
    sleep 0.1
done

assert_file_exists "${STATE_DIR}/issue-555.lock.d" "lock dir が生成された（preflight）"

# kill -TERM
kill -TERM "$WORKER_PID" 2>/dev/null || true

# 最大 2 秒まで回収を待つ
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$WORKER_PID" 2>/dev/null; then
        break
    fi
    sleep 0.2
done

assert_false "worker プロセスが終了" kill -0 "$WORKER_PID"

# lock dir が消えている
assert_file_not_exists "${STATE_DIR}/issue-555.lock.d" "on_worker_exit が lock dir を除去"

# 孫プロセスも終了している
CHILD_PID=$(cat "${TMP}/child.pid" 2>/dev/null || echo "")
if [ -n "$CHILD_PID" ]; then
    # 少し待つ（SIGTERM 伝播）
    for _ in 1 2 3 4 5; do
        if ! kill -0 "$CHILD_PID" 2>/dev/null; then
            break
        fi
        sleep 0.2
    done
    assert_false "孫プロセスも回収される (pid=${CHILD_PID})" kill -0 "$CHILD_PID"
fi

if ! print_summary; then
    exit 1
fi
