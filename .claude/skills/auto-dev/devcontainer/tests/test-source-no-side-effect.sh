#!/usr/bin/env bash
# test-source-no-side-effect.sh — Issue #159 F9/F10/F11 回帰防止（exoloop 配布版）
#
# 検証観点（AC1-AC4）:
#   AC1: `ISSUE_NUM=999 source lib/process-issue.sh` しても gh / claude の
#        mock invocation が 0（dispatcher 発火なし = 副作用ゼロ）
#   AC2: source 後に derive_phase / find_linked_pr / run_claude が関数として
#        定義されている（ヘルパは使える）
#   AC3: source 前に設定した AUTO_DEV_CURRENT_PHASE が保持される
#        （main() 内の代入が source 経路では走らない）
#   AC4: bash lib/process-issue.sh 999 は従来通り dispatcher 発火
#        （mock gh が最低 1 回呼ばれる）
#
# 備考:
#   exoloop 配布版は自分自身の lib/process-issue.sh のみを検証対象とする。
#   main 版との parity は main リポジトリ側の同名テストが担保する。
#
# 背景:
#   Issue #157 実装中に、ISSUE_NUM を親から継承したまま process-issue.sh を
#   source した結果、dispatcher が意図せず発火し budget が浪費されたため、
#   main() ラップ + reset_auto_dev_env による二重防御が Issue #159 で入った。
#   本テストは両方の防御が機能することを mock で検証する。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/test-helper.sh"
reset_auto_dev_env

echo "=== source-no-side-effect tests (exoloop) ==="

SH_FILE="${SCRIPT_DIR}/../lib/process-issue.sh"

if [ ! -f "$SH_FILE" ]; then
    echo "  ! SKIP: $SH_FILE not found"
    exit 0
fi

echo "--- target: ${SH_FILE} ---"

TMP=$(make_tmp_dir "src-no-sfx")
BIN=$(mock_bin_dir)
export PATH="${BIN}:${PATH}"
mkdir -p "${TMP}/logs" "${TMP}/state"

# gh / claude を侵入検知 mock に置換。
# AC4 では derive_phase が `gh issue view --json comments` を呼ぶので、
# `issue view` のときだけ空配列 JSON を返し、後続の jq が crash しないようにする。
COUNTER="${TMP}/invocations.txt"
: > "$COUNTER"
cat > "${BIN}/gh" <<GH_MOCK
#!/usr/bin/env bash
# invocation 記録（呼び出しごとに 1 行）
printf 'gh %s\n' "\$*" >> "$COUNTER"
case "\$*" in
    *"issue view"*)
        echo '[]'
        ;;
    *"pr list"*)
        echo '[]'
        ;;
    *"pr view"*)
        echo '{}'
        ;;
    *)
        echo ''
        ;;
esac
exit 0
GH_MOCK
chmod +x "${BIN}/gh"

cat > "${BIN}/claude" <<CLAUDE_MOCK
#!/usr/bin/env bash
printf 'claude %s\n' "\$*" >> "$COUNTER"
exit 0
CLAUDE_MOCK
chmod +x "${BIN}/claude"

# ----------------------------------------------------------------
# AC1: ISSUE_NUM=999 source で gh / claude が 1 度も呼ばれない
# ----------------------------------------------------------------
(
    export ISSUE_NUM=999
    export LOG_DIR="${TMP}/logs"
    export STATE_DIR="${TMP}/state"
    export AUTO_DEV_REPO="test/repo"
    # shellcheck disable=SC1090
    source "$SH_FILE"
) >/dev/null 2>&1 || true

invocations=$(wc -l < "$COUNTER" | tr -d ' ')
assert_eq "0" "$invocations" "AC1: ISSUE_NUM=999 source しても gh/claude が呼ばれない"

# ----------------------------------------------------------------
# AC2: source 後にヘルパ関数が定義されている
# ----------------------------------------------------------------
ac2_result=$(
    export ISSUE_NUM=999 LOG_DIR="${TMP}/logs" STATE_DIR="${TMP}/state" \
           AUTO_DEV_REPO="test/repo"
    # shellcheck disable=SC1090
    source "$SH_FILE" >/dev/null 2>&1 || true
    missing=""
    for fn in derive_phase find_linked_pr run_claude; do
        if ! declare -f "$fn" >/dev/null 2>&1; then
            missing="${missing} ${fn}"
        fi
    done
    if [ -z "$missing" ]; then
        echo "ok"
    else
        echo "missing:${missing}"
    fi
)
assert_eq "ok" "$ac2_result" "AC2: source 後に derive_phase / find_linked_pr / run_claude が定義される"

# ----------------------------------------------------------------
# AC3: 事前設定した AUTO_DEV_CURRENT_PHASE が保持される
# ----------------------------------------------------------------
ac3_result=$(
    export ISSUE_NUM=999 AUTO_DEV_CURRENT_PHASE="preserved" \
           LOG_DIR="${TMP}/logs" STATE_DIR="${TMP}/state" \
           AUTO_DEV_REPO="test/repo"
    # shellcheck disable=SC1090
    source "$SH_FILE" >/dev/null 2>&1 || true
    echo "${AUTO_DEV_CURRENT_PHASE:-UNSET}"
)
assert_eq "preserved" "$ac3_result" "AC3: source で AUTO_DEV_CURRENT_PHASE が上書きされない"

# ----------------------------------------------------------------
# AC4: bash 直接実行で dispatcher が発火する（回帰防止）
# ----------------------------------------------------------------
: > "$COUNTER"
(
    export LOG_DIR="${TMP}/logs" STATE_DIR="${TMP}/state" \
           AUTO_DEV_REPO="test/repo"
    timeout 10 bash "$SH_FILE" 999 >/dev/null 2>&1 || true
)
invocations_direct=$(wc -l < "$COUNTER" | tr -d ' ')
if [ "$invocations_direct" -gt 0 ]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  ✓ AC4: bash 直接実行で dispatcher 発火 (gh mock 呼出 ${invocations_direct} 回)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("AC4: bash 直接実行で dispatcher 発火")
    echo "  ✗ AC4: bash 直接実行で dispatcher 発火"
    echo "    expected: >0 invocations"
    echo "    actual:   ${invocations_direct}"
fi

# ----------------------------------------------------------------
# サブシェル隔離確認: 本体側に ISSUE_NUM / AUTO_DEV_CURRENT_PHASE が漏れていない
# ----------------------------------------------------------------
assert_eq "" "${ISSUE_NUM:-}" "隔離確認: テスト本体に ISSUE_NUM が漏れていない"
assert_eq "" "${AUTO_DEV_CURRENT_PHASE:-}" "隔離確認: テスト本体に AUTO_DEV_CURRENT_PHASE が漏れていない"

echo ""
if ! print_summary; then
    exit 1
fi
