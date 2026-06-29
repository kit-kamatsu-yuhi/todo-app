#!/bin/bash
# Dispatcher: parallel worker management for auto-dev
#
# Manages concurrent issue processing with slot-based throttling.

# dispatch_workers WORKER_CMD "issue1 issue2 ..." PIDS_VAR
#   Launches workers up to MAX_CONCURRENT, waiting for a slot when full.
#   PIDS_VAR is the name of an array variable to store launched PIDs.
dispatch_workers() {
    local worker_cmd="$1"
    local issues="$2"
    local -n pids_ref="$3"
    local max_concurrent="${AUTO_DEV_MAX_CONCURRENT:-10}"
    pids_ref=()

    for issue_num in $issues; do
        # Wait for a free slot if at capacity
        while [ ${#pids_ref[@]} -ge "$max_concurrent" ]; do
            local new_pids=()
            for pid in "${pids_ref[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    new_pids+=("$pid")
                fi
            done
            pids_ref=("${new_pids[@]}")

            if [ ${#pids_ref[@]} -ge "$max_concurrent" ]; then
                wait -n "${pids_ref[@]}" 2>/dev/null || true
            fi
        done

        echo "[dispatcher] Launching worker for issue #${issue_num} (slot $((${#pids_ref[@]} + 1))/${max_concurrent})"
        "$worker_cmd" "$issue_num" "${STATE_DIR:-/var/auto-dev/state}" &
        pids_ref+=($!)
    done
}

# wait_all_workers PIDS_ARRAY
#   Waits for all workers to complete. Returns count of failures.
wait_all_workers() {
    local -n pids_ref="$1"
    local failures=0
    for pid in "${pids_ref[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            failures=$((failures + 1))
        fi
    done
    return "$failures"
}
