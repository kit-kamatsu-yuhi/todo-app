#!/usr/bin/env bash
# test-pr-detection.sh — find_linked_pr のエッジケース（Issue #148 AC-2）
#
# 検証観点:
#   1. worker crash 後のコメント不在でも実 PR が検出される（gh pr list --search で拾う）
#   2. 別 Issue の無関係 PR は拾わない
#   3. draft PR も検出対象（gh が draft:true を返しても OK）
#   4. MERGED > OPEN > CLOSED の優先順（マージ済みを最優先）
#
# 契約:
#   find_linked_pr <issue_num>
#     → stdout に PR 番号 1 行を出す（該当無しは空文字 / exit 0）
#   gh は mock を PATH に挟んで切替える。
#
# 実装配置:
#   lib/process-issue.sh 内の find_linked_pr、あるいは独立 lib/pr.sh を想定。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"
reset_auto_dev_env

SH_FILE=""
for cand in \
    "${SCRIPT_DIR}/../lib/pr.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/pr.sh" \
    "${SCRIPT_DIR}/../lib/process-issue.sh" \
    "${SCRIPT_DIR}/../devcontainer/lib/process-issue.sh"; do
    if [ -f "$cand" ]; then
        SH_FILE="$cand"
        # find_linked_pr を含むかざっくり確認
        if grep -q 'find_linked_pr' "$cand"; then
            break
        fi
    fi
done

echo "=== find_linked_pr edge case tests ==="

if [ -z "$SH_FILE" ]; then
    echo "  ! SKIP: find_linked_pr source not yet present"
    exit 0
fi

TMP=$(make_tmp_dir "pr-detection")
BIN=$(mock_bin_dir); export PATH="${BIN}:${PATH}"

# gh の mock を作成するヘルパ
# シナリオは GH_MOCK_SCENARIO 環境変数で切替える
make_gh_mock() {
    cat > "${BIN}/gh" <<'GH'
#!/usr/bin/env bash
# mock gh for find_linked_pr tests
args="$*"
scenario="${GH_MOCK_SCENARIO:-empty}"
# 引数に応じて分岐
case "$scenario" in
  worker_crash)
    # Issue コメントは空、pr list で当該 PR を返す
    if [[ "$args" == *"issue view"* && "$args" == *"--comments"* ]]; then
      echo '{"comments":[]}'
      exit 0
    fi
    if [[ "$args" == *"pr list"* ]]; then
      echo '[{"number":42,"state":"OPEN","isDraft":false,"headRefName":"feature/148-x"}]'
      exit 0
    fi
    echo '[]'; exit 0
    ;;
  unrelated_pr)
    # 別 Issue 用の PR しか存在しない
    if [[ "$args" == *"pr list"* ]]; then
      echo '[{"number":999,"state":"OPEN","isDraft":false,"headRefName":"feature/9999-other"}]'
      exit 0
    fi
    echo '[]'; exit 0
    ;;
  draft_pr)
    if [[ "$args" == *"pr list"* ]]; then
      echo '[{"number":7,"state":"OPEN","isDraft":true,"headRefName":"feature/148-y"}]'
      exit 0
    fi
    echo '[]'; exit 0
    ;;
  merged_wins)
    # MERGED / OPEN / CLOSED が混在。MERGED を最優先に返すはず
    if [[ "$args" == *"pr list"* ]]; then
      echo '[
        {"number":10,"state":"CLOSED","isDraft":false,"headRefName":"feature/148-z","closedAt":"2025-01-01T00:00:00Z"},
        {"number":11,"state":"OPEN","isDraft":false,"headRefName":"feature/148-z2"},
        {"number":12,"state":"MERGED","isDraft":false,"headRefName":"feature/148-z3","mergedAt":"2025-02-01T00:00:00Z"}
      ]'
      exit 0
    fi
    echo '[]'; exit 0
    ;;
  *)
    echo '[]'; exit 0
    ;;
esac
GH
    chmod +x "${BIN}/gh"
}
make_gh_mock

for dep in \
    "${SCRIPT_DIR}/../lib/logger.sh" "${SCRIPT_DIR}/../devcontainer/lib/logger.sh" \
    "${SCRIPT_DIR}/../lib/state.sh" "${SCRIPT_DIR}/../devcontainer/lib/state.sh"; do
    [ -f "$dep" ] && source "$dep"
done
# shellcheck disable=SC1090
source "$SH_FILE"

if ! declare -f find_linked_pr >/dev/null 2>&1; then
    echo "  ! FAIL: find_linked_pr not defined"
    exit 1
fi

export AUTO_DEV_REPO="test/repo"
export STATE_DIR="${TMP}/state"
mkdir -p "$STATE_DIR"

call_fn() {
    local scenario="$1" issue="$2"
    local raw num
    raw=$(GH_MOCK_SCENARIO="$scenario" find_linked_pr "$issue" 2>/dev/null | tr -d '\r\n ')
    if [ -z "$raw" ]; then
        printf ''
        return 0
    fi
    # find_linked_pr 出力は { "number": N, ... } 形式。数値だけを返す。
    num=$(printf '%s' "$raw" | jq -r '.number // empty' 2>/dev/null || echo "")
    printf '%s' "$num"
}

# --- 1. worker crash: コメント不在でも PR 検出 -----------------------------
assert_eq "42" "$(call_fn worker_crash 148)" "worker crash 後でも gh pr list で PR 検出"

# --- 2. 無関係 PR は拾わない -----------------------------------------------
result=$(call_fn unrelated_pr 148)
assert_eq "" "$result" "無関係な PR (headRefName が issue 番号を含まない) は拾わない"

# --- 3. draft PR も検出 ---------------------------------------------------
assert_eq "7" "$(call_fn draft_pr 148)" "draft PR も検出対象"

# --- 4. MERGED > OPEN > CLOSED の優先順 ------------------------------------
assert_eq "12" "$(call_fn merged_wins 148)" "MERGED が OPEN / CLOSED より優先"

if ! print_summary; then
    exit 1
fi
