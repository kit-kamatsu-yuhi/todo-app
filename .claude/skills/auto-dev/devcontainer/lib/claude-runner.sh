#!/bin/bash
# Claude CLI runner with FailoverReason-based retry policy.
#
# run_claude_with_retry <prompt>
#   Invokes `claude -p` with both --dangerously-skip-permissions and
#   --permission-mode bypassPermissions (see plan.md Design Decision 1 and 3).
#
#   Retry policy (see hermess-reference.md):
#     auth / billing / context_overflow → no retry, return failure immediately
#     rate_limit / timeout               → exponential backoff, max 2 retries
#     unknown                            → fixed 10s backoff, max 1 retry
#
# Requires: ISSUE_NUM, LOG_DIR, MAX_TURNS, MAX_BUDGET (set by process-issue.sh).
# Sources: logger.sh + error-classify.sh + metrics.sh

if [ -n "${_AUTO_DEV_CLAUDE_RUNNER_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AUTO_DEV_CLAUDE_RUNNER_SOURCED=1

# Resolve LIB_DIR. Prefer the container path, but fall back to the directory
# holding this script (test invocations from macOS host).
if [ -z "${LIB_DIR:-}" ]; then
    if [ -d "/usr/local/lib/auto-dev" ] && [ -f "/usr/local/lib/auto-dev/logger.sh" ]; then
        LIB_DIR="/usr/local/lib/auto-dev"
    else
        LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi
# shellcheck disable=SC1091
source "${LIB_DIR}/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/error-classify.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/metrics.sh"

# _claude_one_attempt <prompt> <log_file>
# Runs a single claude -p invocation and returns its exit code.
_claude_one_attempt() {
    local prompt="$1"
    local log_file="$2"

    set +e
    claude -p "$prompt" \
        --dangerously-skip-permissions \
        --permission-mode bypassPermissions \
        --max-turns "${MAX_TURNS:-200}" \
        --max-budget-usd "${MAX_BUDGET:-5.00}" \
        --output-format json \
        > "$log_file" 2>&1
    local exit_code=$?
    set -e
    return "$exit_code"
}

# Extract cost_usd from the last JSON object in the log file.
_extract_cost() {
    local log_file="$1"
    local cost
    cost=$(tail -n 200 "$log_file" 2>/dev/null \
        | grep -E '^\s*\{' \
        | tail -n 1 \
        | jq -r '.total_cost_usd // .cost_usd // 0' 2>/dev/null \
        || echo "0")
    printf '%s' "$cost"
}

run_claude_with_retry() {
    local prompt="$1"
    local issue="${ISSUE_NUM:-unknown}"
    local phase="${AUTO_DEV_CURRENT_PHASE:-unknown}"
    local log_dir="${LOG_DIR:-/var/auto-dev/logs}"

    # Ensure the log dir exists; fall back to $TMPDIR when the container path
    # is missing (unit tests on macOS host / fresh mount).
    if ! mkdir -p "$log_dir" 2>/dev/null; then
        log_dir="${TMPDIR:-/tmp}/auto-dev-logs"
        mkdir -p "$log_dir" 2>/dev/null || true
    fi

    local attempt=0
    local max_attempts=3   # initial try + up to 2 retries
    local backoff_base="${AUTO_DEV_RETRY_BACKOFF_BASE:-10}"

    # Issue #157 F6: permission_denials counters scoped to this invocation.
    _PERMISSION_DENY_CONSECUTIVE=0
    _PERMISSION_DENY_TOTAL=0

    while : ; do
        attempt=$(( attempt + 1 ))
        local timestamp log_file start end dur_ms cost
        timestamp=$(date +%Y%m%d-%H%M%S)
        log_file="${log_dir}/issue-${issue}-${timestamp}-${phase}-a${attempt}.log"

        log_info "claude_attempt_start" issue="$issue" phase="$phase" attempt="$attempt" log_file="$log_file"

        start=$(_now_ms)
        set +e
        _claude_one_attempt "$prompt" "$log_file"
        local exit_code=$?
        set -e
        end=$(_now_ms)
        dur_ms=$(( end - start ))

        local class
        class=$(classify_claude_error "$log_file" "$exit_code")
        cost=$(_extract_cost "$log_file")

        # Issue #157 F6: count permission_denials in this attempt's log.
        local denial_count
        denial_count=$(grep -c '"permission_denial":true' "$log_file" 2>/dev/null || echo 0)
        denial_count=${denial_count//[^0-9]/}
        denial_count=${denial_count:-0}
        if [ "$denial_count" -gt 0 ]; then
            log_info "permission_deny_detected" issue="$issue" phase="$phase" attempt="$attempt" count="$denial_count"
            _PERMISSION_DENY_CONSECUTIVE=$(( _PERMISSION_DENY_CONSECUTIVE + 1 ))
            _PERMISSION_DENY_TOTAL=$(( _PERMISSION_DENY_TOTAL + denial_count ))
            if [ "$_PERMISSION_DENY_CONSECUTIVE" -ge 3 ] || [ "$_PERMISSION_DENY_TOTAL" -ge 5 ]; then
                log_warn "permission_deny_threshold_reached" issue="$issue" phase="$phase" \
                    consecutive="$_PERMISSION_DENY_CONSECUTIVE" total="$_PERMISSION_DENY_TOTAL"
            fi
        else
            _PERMISSION_DENY_CONSECUTIVE=0
        fi

        log_info "claude_attempt_done" issue="$issue" phase="$phase" attempt="$attempt" \
            exit_code="$exit_code" class="$class" duration_ms="$dur_ms" cost_usd="$cost"

        if [ "$class" = "ok" ] && [ "$exit_code" -eq 0 ]; then
            emit_phase_metric "$issue" "$phase" "$dur_ms" "$cost" "ok" ""
            _LAST_CLAUDE_CLASS="$class"
            _LAST_CLAUDE_ATTEMPTS="$attempt"
            export _LAST_CLAUDE_CLASS _LAST_CLAUDE_ATTEMPTS
            return 0
        fi

        # Non-retryable classifications → fail fast to protect budget.
        case "$class" in
            auth|billing|context_overflow)
                log_error "claude_non_retryable" issue="$issue" phase="$phase" class="$class"
                emit_phase_metric "$issue" "$phase" "$dur_ms" "$cost" "failure" "$class"
                _LAST_CLAUDE_CLASS="$class"
                _LAST_CLAUDE_ATTEMPTS="$attempt"
                export _LAST_CLAUDE_CLASS _LAST_CLAUDE_ATTEMPTS
                return 1
                ;;
        esac

        # rate_limit / timeout → exponential backoff, max 2 retries.
        # unknown → fixed 10s, max 1 retry.
        local remaining=$(( max_attempts - attempt ))
        if [ "$remaining" -le 0 ]; then
            log_error "claude_retries_exhausted" issue="$issue" phase="$phase" class="$class"
            emit_phase_metric "$issue" "$phase" "$dur_ms" "$cost" "failure" "$class"
            _LAST_CLAUDE_CLASS="$class"
            _LAST_CLAUDE_ATTEMPTS="$attempt"
            export _LAST_CLAUDE_CLASS _LAST_CLAUDE_ATTEMPTS
            return 1
        fi

        local backoff
        if [ "$class" = "unknown" ]; then
            if [ "$attempt" -ge 2 ]; then
                log_error "claude_unknown_retry_exhausted" issue="$issue" phase="$phase"
                emit_phase_metric "$issue" "$phase" "$dur_ms" "$cost" "failure" "$class"
                _LAST_CLAUDE_CLASS="$class"
                _LAST_CLAUDE_ATTEMPTS="$attempt"
                export _LAST_CLAUDE_CLASS _LAST_CLAUDE_ATTEMPTS
                return 1
            fi
            backoff="$backoff_base"
        else
            # Exponential: base, base*2, base*4...
            backoff=$(( backoff_base * (1 << (attempt - 1)) ))
        fi

        local max_sleep="${AUTO_DEV_RETRY_MAX_SLEEP:-}"
        if [ -n "$max_sleep" ] && [ "$backoff" -gt "$max_sleep" ]; then
            backoff="$max_sleep"
        fi

        emit_phase_metric "$issue" "$phase" "$dur_ms" "$cost" "retry" "$class"
        log_warn "claude_retry_wait" issue="$issue" phase="$phase" class="$class" backoff_s="$backoff"
        if [ "$backoff" -gt 0 ]; then
            sleep "$backoff" &
            wait $! || true
        fi
    done
}

# run_claude is the public wrapper used by process-issue.sh and tests.
# It accepts either a single positional prompt or the `--prompt <text>` flag.
run_claude() {
    local prompt=""
    case "${1:-}" in
        --prompt)
            prompt="${2:-}"
            ;;
        *)
            prompt="${1:-}"
            ;;
    esac
    run_claude_with_retry "$prompt"
}

export -f run_claude run_claude_with_retry 2>/dev/null || true
