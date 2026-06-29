#!/bin/bash
set -euo pipefail

ISSUE_NUM="${1:-${ISSUE_NUM:-}}"
MAX_TURNS="${AUTO_DEV_MAX_TURNS:-200}"
MAX_BUDGET="${AUTO_DEV_MAX_BUDGET_USD:-5.00}"
LOG_DIR="${LOG_DIR:-/var/auto-dev/logs}"
STATE_DIR="${STATE_DIR:-/var/auto-dev/state}"

# Resolve LIB_DIR. Prefer the container install, fall back to the directory
# that ships with this script so unit tests can source individual helpers.
if [ -z "${LIB_DIR:-}" ]; then
    if [ -d "/usr/local/lib/auto-dev" ] && [ -f "/usr/local/lib/auto-dev/logger.sh" ]; then
        LIB_DIR="/usr/local/lib/auto-dev"
    else
        LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi

export ISSUE_NUM MAX_TURNS MAX_BUDGET LOG_DIR STATE_DIR LIB_DIR

# shellcheck disable=SC1091
source "${LIB_DIR}/logger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/notify.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/phase.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/error-classify.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/metrics.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/claude-runner.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/git-base.sh"

BASE_BRANCH="${BASE_BRANCH:-$(detect_base_branch "${AUTO_DEV_REPO_DIR:-/workspace/repo}")}"
export BASE_BRANCH

# ===========================================
# Git sync helpers
# ===========================================

sync_main() {
    echo "[process-issue] Syncing with origin/${BASE_BRANCH}..."
    git fetch origin "$BASE_BRANCH" 2>/dev/null || true
}

merge_main_into_current() {
    echo "[process-issue] Merging origin/${BASE_BRANCH} into current branch..."
    if ! git merge "origin/${BASE_BRANCH}" --no-edit 2>/dev/null; then
        echo "[process-issue] ⚠️ Merge conflict detected with ${BASE_BRANCH}"
        return 1
    fi
}

# ===========================================
# Find linked PR via gh API
# ===========================================

find_linked_pr() {
    local issue_num="$1"
    gh pr list --repo "${AUTO_DEV_REPO}" \
        --state all \
        --limit 100 \
        --json number,state,url,headRefName,body,createdAt 2>/dev/null \
        | jq --arg n "$issue_num" '
            [.[]
             | select(
                 (.headRefName | startswith("feature/" + $n + "-"))
                 or (.body // "" | test("(?i)(fix|fixes|close|closes|resolve|resolves)[ :]*#" + $n + "(\\b|$)"))
               )
            ]
            | sort_by(
                (if .state == "MERGED" then 2 elif .state == "OPEN" then 1 else 0 end),
                .createdAt
              )
            | last
            | if . == null then empty else {number, state, url, headRefName} end
          ' 2>/dev/null
}

# ===========================================
# Derive phase from issue comments
# ===========================================
#
# The phase derivation remains comment-driven because GitHub is the ground
# truth for human intent. phase.sh's next_phase() is used inside the case
# statement below for explicit error transitions (see T6 in plan.md).

derive_phase() {
    local issue_num="$1"

    local comments
    comments=$(gh issue view "$issue_num" --repo "${AUTO_DEV_REPO}" \
        --json comments -q '.comments' 2>/dev/null || echo "[]")

    local pr_info pr_state
    pr_info=$(find_linked_pr "$issue_num")
    pr_state=$(echo "$pr_info" | jq -r '.state // empty' 2>/dev/null)

    if [ "$pr_state" = "MERGED" ]; then
        echo "done"
        return
    fi

    local last_bot_action last_bot_time
    last_bot_action=$(echo "$comments" | jq -r '
        [.[] | select(.body | test("Auto-dev|📋 実装計画|✅|❌|🤖|⚠️"))]
        | last | .body // ""')
    last_bot_time=$(echo "$comments" | jq -r '
        [.[] | select(.body | test("Auto-dev|📋 実装計画|✅|❌|🤖|⚠️"))]
        | last | .createdAt // ""')

    local user_comment_count=0
    local has_approval=0
    local has_feedback=0

    if [ -n "$last_bot_time" ]; then
        user_comment_count=$(echo "$comments" | jq --arg t "$last_bot_time" '
            [.[] | select(.createdAt > $t) | select(.body | test("Auto-dev|🤖|✅|❌|⚠️") | not)]
            | length')

        has_approval=$(echo "$comments" | jq --arg t "$last_bot_time" '
            [.[] | select(.createdAt > $t)
                 | select(.body | test("Auto-dev|🤖|✅|❌|⚠️") | not)
                 | select(.body | test("(?i)(^ok$|^yes$|^lgtm$|進めろ|進めて|実装して|approve|マージして|merge)"))]
            | length')

        if [ "$user_comment_count" -gt 0 ] && [ "$has_approval" -eq 0 ]; then
            has_feedback=1
        fi
    fi

    local has_plan
    has_plan=$(echo "$comments" | jq '[.[] | select(.body | test("📋 実装計画"))] | length')

    if [ "$has_plan" -eq 0 ]; then
        echo "plan"
        return
    fi

    if [ "$pr_state" = "OPEN" ]; then
        if [ "$has_approval" -gt 0 ]; then
            echo "merge"
        elif [ "$has_feedback" -eq 1 ]; then
            echo "revise-pr"
        else
            echo "wait-review"
        fi
        return
    fi

    if [ "$has_approval" -gt 0 ]; then
        echo "implement"
    elif [ "$has_feedback" -eq 1 ]; then
        echo "replan"
    else
        echo "wait-plan"
    fi
}

get_user_feedback() {
    local issue_num="$1"
    local comments
    comments=$(gh issue view "$issue_num" --repo "${AUTO_DEV_REPO}" \
        --json comments -q '.comments' 2>/dev/null || echo "[]")

    local last_bot_time
    last_bot_time=$(echo "$comments" | jq -r '
        [.[] | select(.body | test("Auto-dev|📋 実装計画|✅|❌|🤖|⚠️"))]
        | last | .createdAt // ""')

    if [ -n "$last_bot_time" ]; then
        echo "$comments" | jq -r --arg t "$last_bot_time" '
            [.[] | select(.createdAt > $t)
                 | select(.body | test("Auto-dev|🤖|✅|❌|⚠️") | not)]
            | map(.body) | join("\n---\n")'
    fi
}

get_pr_url() {
    local issue_num="$1"
    find_linked_pr "$issue_num" | jq -r '.url // empty' 2>/dev/null
}

# --- Helper: run claude ---
# Back-compat shim. Delegates to claude-runner.sh which applies Hermess-style
# retry policy with --permission-mode bypassPermissions inheritance.
run_claude() {
    local prompt="$1"
    run_claude_with_retry "$prompt"
}

# Helper: mark failure state using the state machine explicitly.
#
# IMPORTANT: 呼び出し側は **notify_github_comment で ❌ 失敗コメントを先に投稿し、
# その後で _fail_phase を呼ぶ**こと。state ファイルを先に書くと、続くコメント投稿で
# Issue の updatedAt が state_mtime より後になり、次スキャンの
# is_issue_completed() が activity_ts > state_mtime と判断して
# 同じ Issue を無限に再処理してしまう（P1 フィードバック反映）。
_fail_phase() {
    local from_phase="$1"
    local reason="${2:-error}"
    local next
    next=$(next_phase "$from_phase" "error")
    if [ "$next" = "failure" ]; then
        set_issue_state "$ISSUE_NUM" "failure" 2>/dev/null || true
    fi
    log_error "phase_failed" issue="$ISSUE_NUM" phase="$from_phase" reason="$reason" next="$next"
}

# ===========================================
# Determine phase and act
# ===========================================
#
# Issue #159 F9: dispatcher 全体を main() でラップし、source 時の意図しない
# 発火を構造的に防ぐ。親プロセスから継承した ISSUE_NUM が残っていても、
# main() を呼ばない限り副作用は起きない。
main() {
    # When sourced by unit tests (no ISSUE_NUM), stop here so callers can
    # exercise individual helpers without triggering phase dispatch.
    if [ -z "${ISSUE_NUM:-}" ]; then
        return 0
    fi

    local PHASE
    PHASE=$(derive_phase "$ISSUE_NUM")
    export AUTO_DEV_CURRENT_PHASE="$PHASE"
    log_info "phase_selected" issue="$ISSUE_NUM" phase="$PHASE"
    echo "[process-issue] Issue #${ISSUE_NUM} phase: ${PHASE}"

    local BRANCH PR_URL PR_NUMBER SLUG PROMPT FEEDBACK
    local RC CLASS ATTEMPTS PLAN_POSTED LATEST_LOG BODY NEW_COMMITS

    case "$PHASE" in

    # --- Create plan ---
    "plan")
        notify_github_comment "$ISSUE_NUM" "🤖 Auto-dev: 実装計画を作成中..."

        PROMPT="Issue #${ISSUE_NUM} の実装計画を立てて、Issue にコメントとして投稿する。

1. gh issue view ${ISSUE_NUM} --repo ${AUTO_DEV_REPO} で Issue の内容を確認する
2. コードベースを読み、影響範囲を把握する
3. Skill ツールで /plan-issue を呼び出し、以下の観点で実装計画を策定する:
   - 要件分析（受入基準の明確化）
   - UML設計（Mermaid記法でクラス図・シーケンス図）
   - API設計（エンドポイント・リクエスト・レスポンス定義）
   - DB設計（テーブル変更・マイグレーション）
   - テスト計画（テストケース一覧）
   - タスク分解（実装順序・依存関係）
   - リスク分析（技術的リスク・影響範囲）
4. 設計が複雑な場合は codex-design エージェントを Agent ツールで起動して詳細設計を委譲する（Codex CLI 未インストール時は Claude 単体で代替）
5. Issue が「新プロダクト企画」レベルの大きなスコープの場合は /plan-product の手法（ニーズ検証→要件定義→Issue分割）を適用する
6. plan.md の末尾に以下の「実行フロー」セクションを必ず含めること（チェーン断裂防止）:
## 実行フロー
1. ✅ /plan-issue — 実装計画の策定（完了）
2. ⬜ /codex-team all — 実装・テスト・レビュー（codex-implement + codex-test → acceptance-criteria-agent → codex-review + review-agent）
3. ⬜ /create-pr — PR 作成（/walkthrough → changes.md → PR）
7. gh issue comment ${ISSUE_NUM} --repo ${AUTO_DEV_REPO} で計画を Issue にコメントする
   - コメントの先頭に「## 📋 実装計画」と記載する

制約:
- コードの変更・コミット・PR作成はしない（計画のみ。/plan-issue 完了後に /codex-team を呼び出さないこと）
- ユーザーへの確認は不要（自律実行モード）"

        set +e
        run_claude "$PROMPT"
        RC=$?
        set -e
        CLASS="${_LAST_CLAUDE_CLASS:-unknown}"
        ATTEMPTS="${_LAST_CLAUDE_ATTEMPTS:-1}"

        PLAN_POSTED=0
        if [ "$RC" -ne 0 ]; then
            if gh issue view "$ISSUE_NUM" --repo "${AUTO_DEV_REPO}" --json comments -q '.comments[].body' 2>/dev/null \
                | grep -qE '^## 📋 実装計画'; then
                PLAN_POSTED=1
            fi
        fi

        if [ "$RC" -eq 0 ] || [ "$PLAN_POSTED" -eq 1 ]; then
            if [ "$RC" -ne 0 ]; then
                log_warn "plan_comment_detected_after_failure" issue="$ISSUE_NUM" class="$CLASS"
            fi
            notify_github_comment "$ISSUE_NUM" "✅ 実装計画を投稿しました。確認して、OKなら「OK」、修正点があればコメントしてください。"
        else
            LATEST_LOG=$(ls -1t "${LOG_DIR}/issue-${ISSUE_NUM}-"*-plan-*.log 2>/dev/null | head -n 1 || echo "")
            BODY=$(build_failure_comment "plan" "$CLASS" "$ATTEMPTS" "$LATEST_LOG")
            notify_github_comment "$ISSUE_NUM" "$BODY"
            _fail_phase "plan" "run_claude_${CLASS}"
        fi
        ;;

    # --- Update plan with feedback ---
    "replan")
        FEEDBACK=$(get_user_feedback "$ISSUE_NUM")
        notify_github_comment "$ISSUE_NUM" "🤖 Auto-dev: フィードバックを反映して計画を更新中..."

        PROMPT="Issue #${ISSUE_NUM} の実装計画を、ユーザーのフィードバックに基づいて更新する。

1. gh issue view ${ISSUE_NUM} --repo ${AUTO_DEV_REPO} で Issue とコメント履歴を確認する
2. 以下のユーザーフィードバックを反映して計画を更新する:

--- ユーザーフィードバック ---
${FEEDBACK}
--- ここまで ---

3. コードベースを読み、更新された計画の実現可能性を確認する（設計が複雑な場合は codex-design エージェントを Agent ツールで起動。Codex CLI 未インストール時は Claude 単体で代替）
4. gh issue comment ${ISSUE_NUM} --repo ${AUTO_DEV_REPO} で更新した計画を投稿する
   - コメントの先頭に「## 📋 実装計画（更新）」と記載する
   - フィードバックのどの点を反映したか明記する

制約:
- コードの変更・コミット・PR作成はしない（計画の更新のみ）
- ユーザーへの確認は不要（自律実行モード）"

        set +e
        run_claude "$PROMPT"
        RC=$?
        set -e
        CLASS="${_LAST_CLAUDE_CLASS:-unknown}"
        ATTEMPTS="${_LAST_CLAUDE_ATTEMPTS:-1}"

        PLAN_POSTED=0
        if [ "$RC" -ne 0 ]; then
            if gh issue view "$ISSUE_NUM" --repo "${AUTO_DEV_REPO}" --json comments -q '.comments[].body' 2>/dev/null \
                | grep -qE '^## 📋 実装計画（更新）|^## 📋 実装計画'; then
                PLAN_POSTED=1
            fi
        fi

        if [ "$RC" -eq 0 ] || [ "$PLAN_POSTED" -eq 1 ]; then
            if [ "$RC" -ne 0 ]; then
                log_warn "plan_comment_detected_after_failure" issue="$ISSUE_NUM" class="$CLASS"
            fi
            notify_github_comment "$ISSUE_NUM" "✅ 計画を更新しました。確認して、OKなら「OK」、修正点があればコメントしてください。"
        else
            LATEST_LOG=$(ls -1t "${LOG_DIR}/issue-${ISSUE_NUM}-"*-replan-*.log 2>/dev/null | head -n 1 || echo "")
            BODY=$(build_failure_comment "replan" "$CLASS" "$ATTEMPTS" "$LATEST_LOG")
            notify_github_comment "$ISSUE_NUM" "$BODY"
            _fail_phase "replan" "run_claude_${CLASS}"
        fi
        ;;

    # --- Implement and create PR ---
    "implement")
        notify_github_comment "$ISSUE_NUM" "🤖 Auto-dev: 承認確認。実装を開始します..."

        sync_main

        SLUG=$(gh issue view "$ISSUE_NUM" --repo "${AUTO_DEV_REPO}" --json title -q '.title' \
            | tr '[:upper:]' '[:lower:]' \
            | sed 's/[^a-z0-9]/-/g' \
            | sed 's/--*/-/g' \
            | sed 's/^-//;s/-$//' \
            | head -c 40)
        BRANCH="feature/${ISSUE_NUM}-${SLUG}"
        git checkout -b "$BRANCH" "origin/${BASE_BRANCH}" 2>/dev/null || git checkout "$BRANCH"

        PROMPT="Issue #${ISSUE_NUM} を実装してPRを作成する。

1. gh issue view ${ISSUE_NUM} --repo ${AUTO_DEV_REPO} で内容とコメント履歴を確認
2. Issue コメントの「📋 実装計画」と plan.md の「実行フロー」セクションを参照する
3. Skill ツールで /codex-team all を呼び出す。
   - codex-implement + codex-test を Agent ツールで並列起動して実装・テスト
   - acceptance-criteria-agent で受入基準の RED/GREEN 判定
   - codex-review + review-agent を Agent ツールで並列起動してレビュー
   - 受入基準が全 GREEN になるまで最大5回ループ
   - Agent ツール起動失敗時のみ Claude 単体で代替する
4. テスト・lint・型チェックを実行し、エラーがあれば修正
5. Conventional Commits でコミット
6. PR 作成前に git fetch origin ${BASE_BRANCH} && git merge origin/${BASE_BRANCH} --no-edit（コンフリクトがあれば解消）
7. Skill ツールで /create-pr を呼び出して PR を作成する（Fixes #${ISSUE_NUM} を本文に含める）

制約:
- worktree は使用しない（auto-dev コンテナ内では不要）
- ユーザーへの確認は不要（自律実行モード）
- PR サイズは 500行以内を目標"

        set +e
        run_claude "$PROMPT"
        RC=$?
        set -e
        CLASS="${_LAST_CLAUDE_CLASS:-unknown}"
        ATTEMPTS="${_LAST_CLAUDE_ATTEMPTS:-1}"

        # Issue #157 F1: PR-first detection. The run_claude exit code is only a
        # hint — the source of truth is whether a PR actually exists.
        PR_URL=$(gh pr list --repo "${AUTO_DEV_REPO}" --head "$BRANCH" --json url -q '.[0].url' 2>/dev/null || echo "")
        # R1: retry once on network blip.
        if [ -z "$PR_URL" ]; then
            sleep 2
            PR_URL=$(gh pr list --repo "${AUTO_DEV_REPO}" --head "$BRANCH" --json url -q '.[0].url' 2>/dev/null || echo "")
        fi

        if [ -n "$PR_URL" ]; then
            echo "[process-issue] PR created: ${PR_URL}"
            set_issue_state "$ISSUE_NUM" "pr-created" 2>/dev/null || true
            if [ "$RC" -eq 0 ]; then
                notify_github_comment "$ISSUE_NUM" "✅ PR を作成しました: ${PR_URL}
レビューして、OKなら PR に「OK」「LGTM」等を、修正点があればコメントしてください。"
            else
                log_warn "pr_detected_after_nonzero_exit" issue="$ISSUE_NUM" pr_url="$PR_URL" class="$CLASS"
                notify_github_comment "$ISSUE_NUM" "✅ PR を作成しました: ${PR_URL}
⚠️ ${CLASS} により途中で中断しましたが PR は作成済みです。(attempts=${ATTEMPTS})
レビューして、OKなら PR に「OK」「LGTM」等を、修正点があればコメントしてください。"
            fi
        elif [ "$RC" -eq 0 ]; then
            log_warn "pr_not_found_after_success" issue="$ISSUE_NUM" branch="$BRANCH"
            notify_github_comment "$ISSUE_NUM" "⚠️ 実装完了しましたが PR が見つかりません。"
        else
            LATEST_LOG=$(ls -1t "${LOG_DIR}/issue-${ISSUE_NUM}-"*-implement-*.log 2>/dev/null | head -n 1 || echo "")
            BODY=$(build_failure_comment "implement" "$CLASS" "$ATTEMPTS" "$LATEST_LOG")
            notify_github_comment "$ISSUE_NUM" "$BODY"
            _fail_phase "implement" "run_claude_${CLASS}"
        fi

        ;;

    # --- Revise PR based on review feedback ---
    "revise-pr")
        FEEDBACK=$(get_user_feedback "$ISSUE_NUM")
        PR_URL=$(get_pr_url "$ISSUE_NUM")
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
        notify_github_comment "$ISSUE_NUM" "🤖 Auto-dev: レビューフィードバックを反映中..."

        sync_main

        BRANCH=$(gh pr view "$PR_NUMBER" --repo "${AUTO_DEV_REPO}" --json headRefName -q '.headRefName' 2>/dev/null)
        git fetch origin "$BRANCH" 2>/dev/null || true
        git checkout "$BRANCH" 2>/dev/null || true

        if ! merge_main_into_current; then
            notify_github_comment "$ISSUE_NUM" "⚠️ ${BASE_BRANCH} とのマージコンフリクトが発生しました。手動で解消してください。"
            _fail_phase "revise-pr" "merge_conflict"
            return 1
        fi

        PROMPT="Issue #${ISSUE_NUM} の PR #${PR_NUMBER} に対するレビューフィードバックを反映する。

1. Skill ツールで /address-pr-review を呼び出す（引数: PR URL https://github.com/${AUTO_DEV_REPO}/pull/${PR_NUMBER}）
   - PR のインラインコメント・レビューコメントを取得
   - 各コメントの対応方針を決定（Modify / Not needed / Already answered）
2. 修正が必要な場合、Skill ツールで /codex-team review を呼び出す
   - codex-implement: フィードバックに基づくコード修正
   - codex-test: テストの追加・修正
   - codex-review + review-agent: 修正後のセルフレビュー（並列起動）
   - Agent ツール起動失敗時のみ Claude 単体で代替する
3. テスト・lint・型チェックを実行し、エラーがあれば修正
4. Conventional Commits でコミット・プッシュ

Issue のユーザーフィードバック:
--- レビューフィードバック ---
${FEEDBACK}
--- ここまで ---

制約:
- ユーザーへの確認は不要（自律実行モード）"

        set +e
        run_claude "$PROMPT"
        RC=$?
        set -e
        CLASS="${_LAST_CLAUDE_CLASS:-unknown}"
        ATTEMPTS="${_LAST_CLAUDE_ATTEMPTS:-1}"

        # Issue #157 F2: commit-count based rescue. If the branch has advanced
        # past origin/$BASE_BRANCH we treat the run as a partial success even
        # when the exit code is non-zero (e.g. budget cap after successful commits).
        git fetch origin "$BASE_BRANCH" 2>/dev/null || true
        NEW_COMMITS=$(git rev-list --count "origin/${BASE_BRANCH}..HEAD" 2>/dev/null || echo 0)
        NEW_COMMITS=${NEW_COMMITS//[^0-9]/}
        NEW_COMMITS=${NEW_COMMITS:-0}

        if [ "$RC" -eq 0 ] || [ "$NEW_COMMITS" -gt 0 ]; then
            if [ "$RC" -eq 0 ]; then
                notify_github_comment "$ISSUE_NUM" "✅ レビューフィードバックを反映しました。再確認して、OKなら「OK」「LGTM」等をコメントしてください。"
            else
                log_info "revise_remote_advanced" issue="$ISSUE_NUM" commits="$NEW_COMMITS" class="$CLASS"
                notify_github_comment "$ISSUE_NUM" "✅ レビューフィードバックを反映しました。
⚠️ ${CLASS} により途中で中断しましたが ${NEW_COMMITS} 件の commit が追加済みです。(attempts=${ATTEMPTS})
再確認して、OKなら「OK」「LGTM」等をコメントしてください。"
            fi
        else
            log_warn "revise_no_remote_change" issue="$ISSUE_NUM" class="$CLASS"
            LATEST_LOG=$(ls -1t "${LOG_DIR}/issue-${ISSUE_NUM}-"*-revise-pr-*.log 2>/dev/null | head -n 1 || echo "")
            BODY=$(build_failure_comment "revise-pr" "$CLASS" "$ATTEMPTS" "$LATEST_LOG")
            notify_github_comment "$ISSUE_NUM" "$BODY"
            _fail_phase "revise-pr" "run_claude_${CLASS}"
        fi

        ;;

    # --- Merge PR ---
    "merge")
        PR_URL=$(get_pr_url "$ISSUE_NUM")
        PR_NUMBER=$(echo "$PR_URL" | grep -oE '[0-9]+$')
        echo "[process-issue] Merging PR #${PR_NUMBER}..."

        sync_main
        BRANCH=$(gh pr view "$PR_NUMBER" --repo "${AUTO_DEV_REPO}" --json headRefName -q '.headRefName' 2>/dev/null)
        git fetch origin "$BRANCH" 2>/dev/null || true
        git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
        git reset --hard "origin/$BRANCH" 2>/dev/null || true
        if ! merge_main_into_current; then
            notify_github_comment "$ISSUE_NUM" "⚠️ マージ前に ${BASE_BRANCH} とのコンフリクトが検出されました。手動で解消してください。"
            _fail_phase "merge" "merge_conflict"
            return 1
        fi
        git push origin "$BRANCH" 2>/dev/null || true

        if gh pr merge "$PR_NUMBER" --repo "${AUTO_DEV_REPO}" --squash --delete-branch 2>&1; then
            echo "[process-issue] Merged PR #${PR_NUMBER}"
            set_issue_state "$ISSUE_NUM" "merged" 2>/dev/null || true
            notify_github_comment "$ISSUE_NUM" "✅ PR #${PR_NUMBER} をマージしました。"
        else
            notify_github_comment "$ISSUE_NUM" "❌ マージに失敗しました。手動で確認してください。"
            _fail_phase "merge" "gh_pr_merge"
        fi
        ;;

    # --- Waiting states ---
    "wait-plan")
        echo "[process-issue] #${ISSUE_NUM}: プラン承認待ち"
        ;;
    "wait-review")
        echo "[process-issue] #${ISSUE_NUM}: PRレビュー待ち"
        ;;
    "done")
        echo "[process-issue] #${ISSUE_NUM}: 完了済み"
        ;;
    *)
        echo "[process-issue] #${ISSUE_NUM}: Unknown phase '${PHASE}'"
        ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
