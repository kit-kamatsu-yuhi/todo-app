#!/bin/bash
set -euo pipefail

LIB_DIR="/usr/local/lib/auto-dev"

# --- Tool availability check ---
for tool in claude codex; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "[auto-dev] ERROR: Required tool '$tool' is not installed or not in PATH"
        exit 1
    fi
done

# --- Validate environment ---
source "${LIB_DIR}/validate-env.sh"

# --- Configuration ---
POLL_INTERVAL="${AUTO_DEV_POLL_INTERVAL:-600}"
ISSUE_LABEL="${AUTO_DEV_ISSUE_LABEL:-auto-dev}"
MAX_CONCURRENT="${AUTO_DEV_MAX_CONCURRENT:-10}"
STATE_DIR="/var/auto-dev/state"
LOG_DIR="/var/auto-dev/logs"
METRICS_DIR="/var/auto-dev/metrics"
REPO_DIR="/workspace/repo"
HEARTBEAT_INTERVAL="${AUTO_DEV_HEARTBEAT_INTERVAL:-30}"
HEARTBEAT_FILE="${STATE_DIR}/heartbeat"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$METRICS_DIR" 2>/dev/null || true
# plan.md の「共通」§ / AC-6 要件: state / logs / metrics を 0700 に絞る
chmod 0700 "$STATE_DIR" "$LOG_DIR" "$METRICS_DIR" 2>/dev/null || true

# JSONL ログファイルをデフォルト設定する (logger.sh は AUTO_DEV_LOG_FILE があれば append する)
export AUTO_DEV_LOG_FILE="${AUTO_DEV_LOG_FILE:-${LOG_DIR}/auto-dev-$(date +%Y%m%d).jsonl}"

export STATE_DIR LOG_DIR METRICS_DIR AUTO_DEV_REPO AUTO_DEV_MAX_CONCURRENT AUTO_DEV_LOCK_TTL HEARTBEAT_FILE HEARTBEAT_INTERVAL AUTO_DEV_METRICS_DIR="${METRICS_DIR}"

# --- Structured logger ---
# shellcheck disable=SC1091
source "${LIB_DIR}/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/git-base.sh"

# --- Startup: sweep stale locks from previous run ---
clean_stale_locks 2>/dev/null || true

# --- GitHub auth ---
gh auth setup-git 2>/dev/null || true
echo "[auto-dev] GitHub auth: using GITHUB_TOKEN env var"

# --- Clone repository ---
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "[auto-dev] Cloning ${AUTO_DEV_REPO}..."
    git clone "https://github.com/${AUTO_DEV_REPO}.git" "$REPO_DIR"
fi

cd "$REPO_DIR"
git config user.name "auto-dev[bot]"
git config user.email "auto-dev[bot]@users.noreply.github.com"

# Detect upstream default branch (main / master / etc.) once per startup so
# the rest of the loop can reference origin/$BASE_BRANCH consistently.
BASE_BRANCH=$(detect_base_branch "$REPO_DIR")
export BASE_BRANCH
echo "[auto-dev] Base branch: ${BASE_BRANCH}"

# --- Initial dependency install ---
source "${LIB_DIR}/init-project.sh"

# --- Claude auth check ---
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo ""
    echo "=================================================="
    echo "  Claude ログインが必要です"
    echo "=================================================="
    echo ""
    echo "  ANTHROPIC_API_KEY が未設定のため、手動ログインが必要です。"
    echo ""
    echo "  別ターミナルからコンテナに接続して Claude REPL で /login を実行してください:"
    echo ""
    echo "    docker exec -it -u autodev ${HOSTNAME:-auto-dev} claude"
    echo "    # -u autodev を必ず付けること。root 実行だと credentials が"
    echo "    # /root/.claude/ に保存されて worker から参照できない。"
    echo "    # REPL 内で /login （スラッシュ付き）を入力 → 表示される URL で認証"
    echo ""
    echo "  （Claude Code v2.1.114 以降は claude login サブコマンドは廃止。"
    echo "   /login スラッシュコマンドで認証する。）"
    echo ""
    echo "  ログイン完了後、このプロセスが自動的に開始します。"
    echo "=================================================="
    echo ""

    # Login 判定は `claude -p` の output JSON を解析する。auth の有無を問わず
    # (API key / Max subscription OAuth) 透過的に動く。
    #
    #  - "Not logged in" が result に含まれる → 未ログイン（token 消費 0、
    #    duration_api_ms=0 で API 呼出なし）
    #  - subtype=error_max_turns         → API 呼出は成功 = auth 通っている
    #  - is_error=false                  → 完全成功                = auth 通っている
    #  - それ以外の error                → network 等の一過性障害、retry
    #
    # max-turns=2 にしているのは、1 だと auth 通っていても必ず error_max_turns に
    # なるため。2 でも "hi" 程度なら 1 turn で完結することが多い。
    while true; do
        if ! claude --version > /dev/null 2>&1; then
            echo "[auto-dev] claude CLI not installed or broken, retry in 30s..."
            sleep 30
            continue
        fi

        probe_out=$(claude -p "hi" --max-turns 2 --output-format json 2>&1 || true)

        # "Not logged in" の検出（token 消費 0）
        if printf '%s' "$probe_out" | grep -q 'Not logged in'; then
            echo "[auto-dev] Waiting for Claude login... (retry in 30s)"
            sleep 30
            continue
        fi

        # JSON として parse 可能で、auth 成功シグナルがあるかを確認
        if printf '%s' "$probe_out" \
            | jq -e '(.is_error == false) or (.subtype == "error_max_turns") or (.result != null and (.result | test("Not logged in") | not))' \
            > /dev/null 2>&1; then
            echo "[auto-dev] Claude auth confirmed."
            break
        fi

        echo "[auto-dev] Claude probe unclear, retry in 30s..."
        echo "           (last probe: $(printf '%s' "$probe_out" | head -c 200))"
        sleep 30
    done
fi

# --- Graceful shutdown ---
RUNNING=true
trap 'RUNNING=false; echo "[auto-dev] Shutting down gracefully..."' SIGTERM SIGINT

echo ""
echo "[auto-dev] =========================================="
echo "[auto-dev] Auto-dev started"
echo "[auto-dev]   Repo:       ${AUTO_DEV_REPO}"
echo "[auto-dev]   Label:      ${ISSUE_LABEL}"
echo "[auto-dev]   Interval:   ${POLL_INTERVAL}s"
echo "[auto-dev]   Concurrent: ${MAX_CONCURRENT}"
echo "[auto-dev]   Heartbeat:  ${HEARTBEAT_INTERVAL}s (${HEARTBEAT_FILE})"
echo "[auto-dev] =========================================="
echo ""

log_info "auto_dev_started" repo="$AUTO_DEV_REPO" label="$ISSUE_LABEL" \
    poll_interval_s="$POLL_INTERVAL" max_concurrent="$MAX_CONCURRENT" \
    heartbeat_s="$HEARTBEAT_INTERVAL" 2>/dev/null || true

# --- Main polling loop ---
while $RUNNING; do
    # Heartbeat on every loop iteration (not just the idle sleep) so that any
    # operation before the scan is also observable.
    date -Iseconds > "$HEARTBEAT_FILE" 2>/dev/null || true

    echo "[auto-dev] $(date -Iseconds) Scanning issues..."

    # Log rotation
    LOG_RETENTION_DAYS="${AUTO_DEV_LOG_RETENTION_DAYS:-1}"
    find "$LOG_DIR" -name "*.log" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true
    find "$LOG_DIR" -name "*.jsonl" -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null || true

    # Update to latest
    git fetch origin "$BASE_BRANCH" 2>/dev/null || true
    git checkout "$BASE_BRANCH" 2>/dev/null || true
    git reset --hard "origin/${BASE_BRANCH}" 2>/dev/null || true

    # Refresh dependencies
    source "${LIB_DIR}/init-project.sh" 2>/dev/null || true

    # Daily budget check (only if API key mode)
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
        DAILY_LIMIT="${AUTO_DEV_DAILY_BUDGET_USD:-50.00}"
        TODAY=$(date +%Y%m%d)
        DAILY_SPEND=0
        for log in "${LOG_DIR}"/issue-*-${TODAY}*.log; do
            [ -f "$log" ] || continue
            cost=$(jq -r '.cost_usd // 0' "$log" 2>/dev/null || echo 0)
            DAILY_SPEND=$(echo "$DAILY_SPEND + $cost" | bc 2>/dev/null || echo "$DAILY_SPEND")
        done
        OVER_BUDGET=$(echo "$DAILY_SPEND >= $DAILY_LIMIT" | bc 2>/dev/null || echo 0)
        if [ "$OVER_BUDGET" -eq 1 ] 2>/dev/null; then
            echo "[auto-dev] Daily budget exhausted (${DAILY_SPEND} / ${DAILY_LIMIT} USD). Skipping this cycle."
            # Wait with heartbeat so the container still appears healthy.
            ELAPSED=0
            while [ "$ELAPSED" -lt "$POLL_INTERVAL" ] && $RUNNING; do
                date -Iseconds > "$HEARTBEAT_FILE" 2>/dev/null || true
                sleep "$HEARTBEAT_INTERVAL" &
                wait $! || true
                ELAPSED=$((ELAPSED + HEARTBEAT_INTERVAL))
            done
            continue
        fi
    fi

    # Fetch issues with label
    ISSUES=$(gh issue list \
        --repo "${AUTO_DEV_REPO}" \
        --label "${ISSUE_LABEL}" \
        --state open \
        --json number,title \
        --limit "$MAX_CONCURRENT" 2>/dev/null || echo "[]")

    ISSUE_COUNT=$(echo "$ISSUES" | jq 'length')
    echo "[auto-dev] Found ${ISSUE_COUNT} issue(s) with label '${ISSUE_LABEL}'"

    # Filter to eligible issues (not locked, not completed)
    source "${LIB_DIR}/dispatcher.sh"
    ELIGIBLE_ISSUES=""

    while read -r issue; do
        [ -z "$issue" ] && continue
        ISSUE_NUM=$(echo "$issue" | jq -r '.number')
        ISSUE_TITLE=$(echo "$issue" | jq -r '.title')

        echo "[auto-dev] Checking issue #${ISSUE_NUM}: ${ISSUE_TITLE}"

        if is_issue_locked "$ISSUE_NUM"; then
            echo "[auto-dev] #${ISSUE_NUM}: Currently locked, skipping"
            continue
        fi
        if is_issue_completed "$ISSUE_NUM"; then
            CURRENT_STATE=$(get_issue_state "$ISSUE_NUM")
            case "$CURRENT_STATE" in
                merged)
                    echo "[auto-dev] #${ISSUE_NUM}: Already merged, skipping"
                    ;;
                failure)
                    echo "[auto-dev] #${ISSUE_NUM}: Failed previously, awaiting new activity"
                    ;;
                *)
                    echo "[auto-dev] #${ISSUE_NUM}: Already completed, skipping"
                    ;;
            esac
            continue
        fi

        ELIGIBLE_ISSUES="${ELIGIBLE_ISSUES} ${ISSUE_NUM}"
    done < <(echo "$ISSUES" | jq -c '.[]')

    ELIGIBLE_ISSUES="${ELIGIBLE_ISSUES# }"
    if [ -n "$ELIGIBLE_ISSUES" ]; then
        ELIGIBLE_COUNT=$(echo "$ELIGIBLE_ISSUES" | wc -w | tr -d ' ')
        echo "[auto-dev] Dispatching ${ELIGIBLE_COUNT} issue(s) (max concurrent: ${MAX_CONCURRENT})"

        WORKER_PIDS=()
        dispatch_workers "${LIB_DIR}/worker.sh" "$ELIGIBLE_ISSUES" WORKER_PIDS

        for pid in "${WORKER_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        echo "[auto-dev] All workers completed"
    fi

    # Ensure we're back on the base branch
    cd "$REPO_DIR"
    git checkout "$BASE_BRANCH" 2>/dev/null || true
    git reset --hard "origin/${BASE_BRANCH}" 2>/dev/null || true

    # --- Idle wait with heartbeat ---
    # Replace the plain `sleep $POLL_INTERVAL & wait $!` with a ticker that
    # refreshes the heartbeat file every HEARTBEAT_INTERVAL seconds. This
    # keeps WSL2 integration distros from idling and makes the container
    # liveness observable via `docker exec ... cat $HEARTBEAT_FILE`.
    echo "[auto-dev] Next scan in ${POLL_INTERVAL}s (heartbeat ${HEARTBEAT_INTERVAL}s)"
    ELAPSED=0
    while [ "$ELAPSED" -lt "$POLL_INTERVAL" ] && $RUNNING; do
        date -Iseconds > "$HEARTBEAT_FILE" 2>/dev/null || true
        sleep "$HEARTBEAT_INTERVAL" &
        wait $! || true
        ELAPSED=$((ELAPSED + HEARTBEAT_INTERVAL))
    done
done

echo "[auto-dev] Stopped."
log_info "auto_dev_stopped" 2>/dev/null || true
