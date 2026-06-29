#!/bin/bash
# Structured JSON-line logger for auto-dev
#
# Provides log_info / log_warn / log_error / with_duration and masks
# sensitive env values (ANTHROPIC_API_KEY, GITHUB_TOKEN) in output.
#
# Usage:
#   source "${LIB_DIR}/logger.sh"
#   log_info "phase_started" issue=42 phase=implement
#   with_duration "claude_call" run_claude "$prompt"

if [ -n "${_AUTO_DEV_LOGGER_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AUTO_DEV_LOGGER_SOURCED=1

AUTO_DEV_LOG_DIR="${LOG_DIR:-/var/auto-dev/logs}"

# Mask sensitive env values in a string (prints to stdout).
# Empty / unset env values are skipped to avoid matching every char.
mask_secrets() {
    local s="$1"
    local key val
    for key in ANTHROPIC_API_KEY GITHUB_TOKEN GH_TOKEN OPENAI_API_KEY SLACK_WEBHOOK_URL; do
        val="${!key:-}"
        if [ -n "$val" ] && [ "${#val}" -ge 8 ]; then
            # Escape regex metacharacters in the value for sed.
            local escaped
            escaped=$(printf '%s' "$val" | sed 's/[][\\/.^$*+?()|{}]/\\&/g')
            s=$(printf '%s' "$s" | sed "s/${escaped}/***/g")
        fi
    done
    printf '%s' "$s"
}

# Internal: emit one JSON line to stderr (and optional log file).
_emit_log() {
    local level="$1"; shift
    local event="$1"; shift
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build a JSON object. Extra args in key=value form become JSON fields.
    local json fields=""
    local arg key val esc_val
    for arg in "$@"; do
        key="${arg%%=*}"
        val="${arg#*=}"
        # Escape backslashes and double quotes for JSON string values.
        esc_val=$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')
        fields="${fields},\"${key}\":\"${esc_val}\""
    done

    json="{\"ts\":\"${ts}\",\"level\":\"${level}\",\"event\":\"${event}\",\"pid\":${BASHPID:-$$}${fields}}"
    json=$(mask_secrets "$json")

    printf '%s\n' "$json" >&2
    if [ -n "${AUTO_DEV_LOG_FILE:-}" ]; then
        printf '%s\n' "$json" >> "$AUTO_DEV_LOG_FILE" 2>/dev/null || true
    fi
}

log_info()  { _emit_log "info"  "$@"; }
log_warn()  { _emit_log "warn"  "$@"; }
log_error() { _emit_log "error" "$@"; }

# log_event <level> <event_name> [key=value ...]
# Generic entry point. Accepts an explicit level so callers can choose.
log_event() {
    local level="${1:-info}"; shift || true
    _emit_log "$level" "$@"
}

# Portable millisecond clock. GNU date supports %N; BSD date (macOS) does not and
# returns a literal 'N'. Fall back to python or seconds * 1000 in that case.
_now_ms() {
    local out
    out=$(date +%s%3N 2>/dev/null || echo "")
    case "$out" in
        *N*|"") ;;
        *) printf '%s' "$out"; return 0 ;;
    esac
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import time; print(int(time.time()*1000))'
        return 0
    fi
    printf '%s' $(( $(date +%s) * 1000 ))
}

# with_duration <label> <command...>
# Runs the command, emits a metric-like log line with duration_ms and status.
# Returns the command's exit code.
with_duration() {
    local label="$1"; shift
    local start end dur_ms status
    start=$(_now_ms)

    set +e
    "$@"
    status=$?
    set -e

    end=$(_now_ms)
    dur_ms=$(( end - start ))

    if [ "$status" -eq 0 ]; then
        log_info "with_duration" label="$label" duration_ms="$dur_ms" status="ok"
    else
        log_warn "with_duration" label="$label" duration_ms="$dur_ms" status="error" exit_code="$status"
    fi
    return "$status"
}

export -f mask_secrets log_info log_warn log_error log_event with_duration 2>/dev/null || true
