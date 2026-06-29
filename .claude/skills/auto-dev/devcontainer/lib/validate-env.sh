#!/bin/bash
set -euo pipefail

# Validate required environment variables
MISSING=()

[ -z "${GITHUB_TOKEN:-}" ] && MISSING+=("GITHUB_TOKEN")
[ -z "${AUTO_DEV_REPO:-}" ] && MISSING+=("AUTO_DEV_REPO")

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "[auto-dev] ERROR: Missing required environment variables:"
    for var in "${MISSING[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Required:"
    echo "  GITHUB_TOKEN=ghp_...      GitHub PAT (repo, issues, pull-requests scope)"
    echo "  AUTO_DEV_REPO=owner/repo  Target repository (e.g. Clickan/ai-skill-studio)"
    echo ""
    echo "Claude 認証 (default: subscription OAuth login):"
    echo "  docker exec -it -u autodev <container> claude"
    echo "    → REPL 内で '/login' を実行（v2.1.114 以降は subcommand 廃止）"
    echo "  代替: ANTHROPIC_API_KEY=sk-ant-... を .env.agent に設定（subscription なしの場合）"
    echo ""
    echo "Codex CLI 認証 (default: subscription OAuth login):"
    echo "  docker exec -it -u autodev <container> codex login"
    echo "    → 表示 URL を host のブラウザで開いて OAuth 認証"
    echo "  代替: OPENAI_API_KEY=sk-proj-... を .env.agent に設定（subscription なしの場合）"
    echo ""
    echo "  どちらも default は login（subscription）。"
    echo "  subscription を持っていない場合のみ API key を使う。"
    exit 1
fi

# --- Directory writability checks ---
#
# state / logs / metrics directories must exist and be writable by the worker
# user. The container bootstraps them in entrypoint.sh but verify here so a
# botched volume mount or hostile permission fails fast with a clear message.
STATE_DIR_CHK="${STATE_DIR:-/var/auto-dev/state}"
LOG_DIR_CHK="${LOG_DIR:-/var/auto-dev/logs}"
METRICS_DIR_CHK="${AUTO_DEV_METRICS_DIR:-/var/auto-dev/metrics}"

DIR_FAILS=()
for d in "$STATE_DIR_CHK" "$LOG_DIR_CHK" "$METRICS_DIR_CHK"; do
    if ! mkdir -p "$d" 2>/dev/null; then
        DIR_FAILS+=("$d (mkdir failed)")
        continue
    fi
    if [ ! -w "$d" ]; then
        DIR_FAILS+=("$d (not writable)")
    fi
done

if [ ${#DIR_FAILS[@]} -gt 0 ]; then
    echo "[auto-dev] ERROR: Required directories are not writable:"
    for d in "${DIR_FAILS[@]}"; do
        echo "  - $d"
    done
    exit 1
fi

# --- Heartbeat timing check ---
#
# POLL_INTERVAL must be an integer multiple of HEARTBEAT_INTERVAL so the idle
# wait loop exits cleanly without drift. See entrypoint.sh idle loop.
POLL_INTERVAL_V="${AUTO_DEV_POLL_INTERVAL:-600}"
HEARTBEAT_INTERVAL_V="${AUTO_DEV_HEARTBEAT_INTERVAL:-30}"
case "$POLL_INTERVAL_V" in
    ''|*[!0-9]*) echo "[auto-dev] ERROR: AUTO_DEV_POLL_INTERVAL must be a positive integer (got '${POLL_INTERVAL_V}')"; exit 1 ;;
esac
case "$HEARTBEAT_INTERVAL_V" in
    ''|*[!0-9]*) echo "[auto-dev] ERROR: AUTO_DEV_HEARTBEAT_INTERVAL must be a positive integer (got '${HEARTBEAT_INTERVAL_V}')"; exit 1 ;;
esac
if [ "$POLL_INTERVAL_V" -le 0 ]; then
    echo "[auto-dev] ERROR: AUTO_DEV_POLL_INTERVAL must be > 0"
    exit 1
fi
if [ "$HEARTBEAT_INTERVAL_V" -le 0 ]; then
    echo "[auto-dev] ERROR: AUTO_DEV_HEARTBEAT_INTERVAL must be > 0"
    exit 1
fi
if [ $(( POLL_INTERVAL_V % HEARTBEAT_INTERVAL_V )) -ne 0 ]; then
    echo "[auto-dev] ERROR: AUTO_DEV_POLL_INTERVAL (${POLL_INTERVAL_V}) must be a multiple of AUTO_DEV_HEARTBEAT_INTERVAL (${HEARTBEAT_INTERVAL_V})"
    exit 1
fi

echo "[auto-dev] Environment validated."
