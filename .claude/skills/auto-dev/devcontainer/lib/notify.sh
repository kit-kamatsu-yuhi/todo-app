#!/bin/bash
# Notification helpers for auto-dev.
# Delegates log lines to logger.sh so every notification is emitted as a
# structured JSON record alongside the external side effect (gh / slack).

: "${LIB_DIR:=/usr/local/lib/auto-dev}"
# shellcheck disable=SC1091
[ -f "${LIB_DIR}/logger.sh" ] && source "${LIB_DIR}/logger.sh"

notify_github_comment() {
    local issue_num="$1"
    local message="$2"

    if command -v log_info >/dev/null 2>&1; then
        with_duration "notify_github_comment" \
            gh issue comment "$issue_num" \
                --repo "${AUTO_DEV_REPO}" \
                --body "$message" 2>/dev/null || true
    else
        gh issue comment "$issue_num" \
            --repo "${AUTO_DEV_REPO}" \
            --body "$message" 2>/dev/null || true
    fi
}

notify_slack() {
    local message="$1"
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        if command -v log_info >/dev/null 2>&1; then
            with_duration "notify_slack" \
                curl -s -X POST "$SLACK_WEBHOOK_URL" \
                    -H 'Content-type: application/json' \
                    -d "{\"text\":\"$message\"}" 2>/dev/null || true
        else
            curl -s -X POST "$SLACK_WEBHOOK_URL" \
                -H 'Content-type: application/json' \
                -d "{\"text\":\"$message\"}" 2>/dev/null || true
        fi
    fi
}

# Issue #157 F7/F8: failure comment builder.
#
# _mask_secrets replaces common credential patterns with `***` so log tails
# posted to GitHub do not leak tokens.
_mask_secrets() {
    sed -E \
        -e 's/(GITHUB_TOKEN=)ghp_[A-Za-z0-9_]+/\1***/g' \
        -e 's/ghp_[A-Za-z0-9_]{20,}/***/g' \
        -e 's/sk-proj-[A-Za-z0-9_-]+/sk-proj-***/g' \
        -e 's/sk-ant-[A-Za-z0-9_-]+/sk-ant-***/g' \
        -e 's/(x-api-key:[[:space:]]*)[A-Za-z0-9_.-]+/\1***/gi' \
        -e 's/(Bearer[[:space:]]+)[A-Za-z0-9_.-]+/\1***/g' \
        -e 's/(Authorization:[[:space:]]*)[A-Za-z0-9_. -]+/\1***/gi'
}

# build_failure_comment <phase> <class> <attempts> <log_file>
# Echoes a GitHub comment body with <details> for error excerpt + log tail.
# Total size is kept under 60KB (GitHub API caps around 65536 bytes).
build_failure_comment() {
    local phase="$1"
    local class="${2:-unknown}"
    local attempts="${3:-1}"
    local log_file="${4:-}"
    local issue_num="${ISSUE_NUM:-}"
    local max_body_bytes=60000

    local phase_label="実装"
    case "$phase" in
        plan)       phase_label="計画作成" ;;
        replan)     phase_label="計画更新" ;;
        implement)  phase_label="実装" ;;
        revise-pr)  phase_label="フィードバック反映" ;;
    esac

    local header="❌ ${phase_label}に失敗しました。(class=${class}, attempts=${attempts})"
    local error_excerpt="" log_tail=""
    if [ -n "$log_file" ] && [ -s "$log_file" ]; then
        error_excerpt=$(tail -n 200 "$log_file" 2>/dev/null \
            | grep -E '^\s*\{' \
            | tail -n 1 \
            | jq -r '.errors // empty | if type == "array" then join("\n") else tostring end' 2>/dev/null \
            | _mask_secrets \
            | head -c 2000 || true)
        local tail_lines=30
        while [ "$tail_lines" -ge 5 ]; do
            log_tail=$(tail -n "$tail_lines" "$log_file" 2>/dev/null | _mask_secrets || true)
            local body
            body=$(cat <<EOF
${header}

<details><summary>error</summary>

\`\`\`
${error_excerpt:-（エラー本文なし）}
\`\`\`

</details>

<details><summary>log tail (${tail_lines} lines)</summary>

\`\`\`
${log_tail}
\`\`\`

</details>
EOF
)
            if [ "${#body}" -le "$max_body_bytes" ]; then
                if command -v log_info >/dev/null 2>&1; then
                    log_info "failure_comment_posted" issue="$issue_num" phase="$phase" size_bytes="${#body}"
                fi
                printf '%s' "$body"
                return 0
            fi
            tail_lines=$(( tail_lines / 2 ))
        done
        # Fallback: drop log tail when even the shortest variant exceeds the cap.
        local body
        body=$(cat <<EOF
${header}

<details><summary>error</summary>

\`\`\`
${error_excerpt:-（エラー本文なし）}
\`\`\`

</details>

<details><summary>log tail</summary>
(log tail を省略しました。サイズ超過のため)
</details>
EOF
)
        if command -v log_warn >/dev/null 2>&1; then
            log_warn "failure_comment_truncated" issue="$issue_num" phase="$phase" final_size="${#body}"
        fi
        printf '%s' "$body"
        return 0
    fi
    # No log file available — return just the header.
    printf '%s' "$header"
}

export -f build_failure_comment _mask_secrets 2>/dev/null || true
