#!/bin/bash
# Hermess-style FailoverReason classifier for claude CLI output.
#
# classify_claude_error <json_file> [exit_code]
#   Reads the Claude --output-format json log and prints one of:
#     auth | billing | rate_limit | context_overflow | timeout | unknown | ok
#
# The classification drives retry policy in claude-runner.sh.

if [ -n "${_AUTO_DEV_ERROR_CLASSIFY_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AUTO_DEV_ERROR_CLASSIFY_SOURCED=1

classify_claude_error() {
    local json_file="${1:-}"
    local exit_code="${2:-0}"

    # Timeout from `timeout` command → exit 124
    # SIGKILL from parent watchdog → exit 137 (128 + 9)
    if [ "$exit_code" = "124" ] || [ "$exit_code" = "137" ]; then
        printf '%s\n' "timeout"
        return 0
    fi

    # HTTP 429 surfaced as process exit code → rate_limit
    if [ "$exit_code" = "429" ]; then
        printf '%s\n' "rate_limit"
        return 0
    fi

    if [ -z "$json_file" ] || [ ! -s "$json_file" ]; then
        if [ "$exit_code" = "0" ]; then
            printf '%s\n' "ok"
        else
            printf '%s\n' "unknown"
        fi
        return 0
    fi

    # Parse only the last JSON object (claude -p emits one per turn).
    local last_json
    last_json=$(tail -n 200 "$json_file" 2>/dev/null \
        | grep -E '^\s*\{' \
        | tail -n 1)

    if [ -z "$last_json" ]; then
        if [ "$exit_code" = "0" ]; then
            printf '%s\n' "ok"
        else
            printf '%s\n' "unknown"
        fi
        return 0
    fi

    local is_error subtype errors_blob
    is_error=$(printf '%s' "$last_json" | jq -r '.is_error // false' 2>/dev/null || echo "false")
    subtype=$(printf '%s' "$last_json" | jq -r '.subtype // ""' 2>/dev/null || echo "")
    errors_blob=$(printf '%s' "$last_json" | jq -r '(.errors // []) | join(" ")' 2>/dev/null || echo "")

    if [ "$is_error" != "true" ] && [ "$exit_code" = "0" ]; then
        printf '%s\n' "ok"
        return 0
    fi

    # auth
    case "$subtype" in
        *auth*|*invalid_api_key*|*authentication*)
            printf '%s\n' "auth"; return 0 ;;
    esac
    if printf '%s' "$errors_blob" | grep -qiE 'invalid api key|auth|unauthorized'; then
        printf '%s\n' "auth"
        return 0
    fi

    # billing / budget
    case "$subtype" in
        *error_max_budget_usd*|*budget*)
            printf '%s\n' "billing"; return 0 ;;
    esac
    if printf '%s' "$errors_blob" | grep -qiE 'maximum budget|budget exceeded|insufficient credit'; then
        printf '%s\n' "billing"
        return 0
    fi

    # rate_limit
    case "$subtype" in
        *rate_limit*|*error_rate_limit*|*429*)
            printf '%s\n' "rate_limit"; return 0 ;;
    esac
    if printf '%s' "$errors_blob" | grep -qiE 'rate.?limit|429|too many requests'; then
        printf '%s\n' "rate_limit"
        return 0
    fi

    # context_overflow
    case "$subtype" in
        *error_max_tokens*|*context_overflow*|*context_length*)
            printf '%s\n' "context_overflow"; return 0 ;;
    esac
    if printf '%s' "$errors_blob" | grep -qiE 'context length|max.?tokens|context window'; then
        printf '%s\n' "context_overflow"
        return 0
    fi

    # timeout signals from subtype
    case "$subtype" in
        *timeout*|*timed_out*)
            printf '%s\n' "timeout"; return 0 ;;
    esac

    printf '%s\n' "unknown"
    return 0
}

# is_retryable <class>
# Returns 0 for rate_limit / timeout / unknown, non-zero otherwise.
is_retryable() {
    case "${1:-}" in
        rate_limit|timeout|unknown) return 0 ;;
        *) return 1 ;;
    esac
}

# classify_error <exit_code> <stdout_json_or_path>
# Convenience wrapper with argument order matching test-error-classify.sh contract.
# The second argument may be either a path to a JSON file or an inline JSON string.
classify_error() {
    local exit_code="${1:-0}"
    local payload="${2:-}"
    local tmp=""

    if [ -z "$payload" ]; then
        classify_claude_error "" "$exit_code"
        return 0
    fi

    if [ -f "$payload" ]; then
        classify_claude_error "$payload" "$exit_code"
        return 0
    fi

    # Inline JSON string → write to a temp file and classify.
    tmp=$(mktemp 2>/dev/null) || tmp="/tmp/classify-$$.json"
    printf '%s\n' "$payload" > "$tmp"
    classify_claude_error "$tmp" "$exit_code"
    rm -f "$tmp" 2>/dev/null || true
}

export -f classify_claude_error classify_error is_retryable 2>/dev/null || true
