#!/bin/bash
# Daily JSONL metrics sink for auto-dev.
#
# emit_phase_metric <issue> <phase> <duration_ms> <cost_usd> <status> <error_class>
#   Appends one JSON object to /var/auto-dev/metrics/daily-YYYYMMDD.jsonl.

if [ -n "${_AUTO_DEV_METRICS_SOURCED:-}" ]; then
    return 0 2>/dev/null || true
fi
_AUTO_DEV_METRICS_SOURCED=1

AUTO_DEV_METRICS_DIR="${AUTO_DEV_METRICS_DIR:-/var/auto-dev/metrics}"

emit_phase_metric() {
    local issue="${1:-}"
    local phase="${2:-}"
    local duration_ms="${3:-0}"
    local cost_usd="${4:-0}"
    local status="${5:-unknown}"
    local error_class="${6:-}"

    local ts today file
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    today=$(date -u +"%Y%m%d")
    file="${AUTO_DEV_METRICS_DIR}/daily-${today}.jsonl"

    mkdir -p "$AUTO_DEV_METRICS_DIR" 2>/dev/null || true

    # Numeric fields are emitted as strings to avoid JSON parse failures when
    # the caller passes empty values. jq consumers can cast with tonumber.
    local line
    line=$(printf '{"ts":"%s","issue":"%s","phase":"%s","duration_ms":"%s","cost_usd":"%s","status":"%s","error_class":"%s"}' \
        "$ts" "$issue" "$phase" "$duration_ms" "$cost_usd" "$status" "$error_class")

    printf '%s\n' "$line" >> "$file" 2>/dev/null || true
}

export -f emit_phase_metric 2>/dev/null || true
