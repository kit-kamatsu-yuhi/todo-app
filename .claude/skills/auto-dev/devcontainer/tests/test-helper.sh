#!/usr/bin/env bash
# test-helper.sh — auto-dev テスト共通ヘルパ（Issue #148 拡張版）
#
# 既存呼び出し元（test-merge-sync.sh / run-all.sh 等）の後方互換を維持しつつ、
# Issue #148 の新規テスト群（lock-race / pr-detection / claude-retry / heartbeat 等）
# が必要とする assert / mock / 一時 dir 作成ヘルパを追加する。
#
# 提供する API:
#   変数:
#     TESTS_RUN / TESTS_PASSED / TESTS_FAILED / FAILED_TESTS
#     TEST_TMP_DIR  — 各 test ファイルが自前で setup する共通 tmp dir（trap cleanup 推奨）
#   assert:
#     assert_eq <expected> <actual> [msg]
#     assert_ne <not_expected> <actual> [msg]
#     assert_true <msg> <cmd...>
#     assert_false <msg> <cmd...>
#     assert_file_exists <path> [msg]
#     assert_file_not_exists <path> [msg]
#     assert_file_contains <path> <grep-pattern> [msg]
#     assert_file_not_contains <path> <grep-pattern> [msg]
#     assert_json_valid <path-or-string> [msg]
#     assert_json_eq <jq-expr> <expected> <path> [msg]
#     assert_contains <haystack> <needle> [msg]
#     assert_not_contains <haystack> <needle> [msg]
#   tmp / mock:
#     make_tmp_dir [prefix]           — mktemp -d し echo でパスを返す
#     register_cleanup <path>         — EXIT trap で rm -rf する
#     mock_bin_dir                    — PATH 先頭に追加する stub 用 dir を作って echo
#     install_stub <bin_dir> <name> <script> — stub を配置して chmod +x
#     mock_gh <bin_dir> [exit_code]   — gh を stub 化（デフォルト exit 0 / 空出力）
#     mock_docker <bin_dir> [exit]    — docker を stub 化
#     mock_claude <bin_dir> <exit> [stdout_json] — claude CLI の簡易 stub
#   結果表示:
#     print_summary                   — PASS/FAIL の集計を出す。exit code = TESTS_FAILED

# 注意: set -e は呼出元に委ねる（set -u は後方互換のため強制しない）
# shellcheck disable=SC2034

TESTS_RUN=${TESTS_RUN:-0}
TESTS_PASSED=${TESTS_PASSED:-0}
TESTS_FAILED=${TESTS_FAILED:-0}
FAILED_TESTS=${FAILED_TESTS:-}
if ! declare -p FAILED_TESTS >/dev/null 2>&1 || [ "$(declare -p FAILED_TESTS 2>/dev/null | awk '{print $2}')" != "-a" ]; then
    FAILED_TESTS=()
fi

# ---- 登録された cleanup パスを一括削除 --------------------------------------
__HELPER_CLEANUP_PATHS=()
__helper_run_cleanups() {
    local p
    for p in "${__HELPER_CLEANUP_PATHS[@]:-}"; do
        [ -n "${p:-}" ] || continue
        rm -rf -- "$p" 2>/dev/null || true
    done
}
register_cleanup() {
    __HELPER_CLEANUP_PATHS+=("$1")
}
trap __helper_run_cleanups EXIT

# ---- assertions -------------------------------------------------------------

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-values equal}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    expected: '${expected}'"
        echo "    actual:   '${actual}'"
    fi
}

assert_ne() {
    local not_expected="$1" actual="$2" msg="${3:-values differ}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$not_expected" != "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    both values: '${actual}'"
    fi
}

assert_true() {
    local msg="${1:-command succeeds}"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
    fi
}

assert_false() {
    local msg="${1:-command fails}"
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists: $1}"
    assert_true "$msg" test -e "$path"
}

assert_file_not_exists() {
    local path="$1" msg="${2:-file absent: $1}"
    assert_false "$msg" test -e "$path"
}

assert_file_contains() {
    local path="$1" pattern="$2" msg="${3:-$(basename "$1") contains /${2}/}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -f "$path" ] && grep -Eq -- "$pattern" "$path"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        [ -f "$path" ] || echo "    (file missing: $path)"
    fi
}

assert_file_not_contains() {
    local path="$1" pattern="$2" msg="${3:-$(basename "$1") does not contain /${2}/}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ ! -f "$path" ] || ! grep -Eq -- "$pattern" "$path"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
    fi
}

# 引数がファイルなら cat、そうでなければ文字列として jq にパイプ。
# jq が無い環境では python3 -c 'json.loads(...)' にフォールバック。
assert_json_valid() {
    local input="$1" msg="${2:-valid JSON}"
    TESTS_RUN=$((TESTS_RUN + 1))
    local data
    if [ -f "$input" ]; then
        data=$(cat "$input")
    else
        data="$input"
    fi
    local ok=1
    if command -v jq >/dev/null 2>&1; then
        if printf '%s' "$data" | jq -e . >/dev/null 2>&1; then
            ok=0
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if printf '%s' "$data" | python3 -c 'import sys,json; json.loads(sys.stdin.read())' >/dev/null 2>&1; then
            ok=0
        fi
    else
        echo "  ! skipping (no jq/python3): ${msg}"
        TESTS_RUN=$((TESTS_RUN - 1))
        return 0
    fi
    if [ "$ok" -eq 0 ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    input: ${data}"
    fi
}

# jq expression を評価して expected と比較。jq 必須。
assert_json_eq() {
    local expr="$1" expected="$2" path="$3" msg="${4:-jq ${expr} == ${expected}}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if ! command -v jq >/dev/null 2>&1; then
        echo "  ! skipping (no jq): ${msg}"
        TESTS_RUN=$((TESTS_RUN - 1))
        return 0
    fi
    local actual
    actual=$(jq -r "$expr" "$path" 2>/dev/null || echo "__JQ_ERR__")
    if [ "$actual" = "$expected" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    expected: '${expected}'"
        echo "    actual:   '${actual}'"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-contains: ${needle}}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "${haystack#*${needle}}" != "$haystack" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    haystack: '${haystack}'"
        echo "    needle:   '${needle}'"
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" msg="${3:-does not contain: ${needle}}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "${haystack#*${needle}}" = "$haystack" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ ${msg}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$msg")
        echo "  ✗ ${msg}"
        echo "    haystack: '${haystack}'"
        echo "    needle:   '${needle}'"
    fi
}

# ---- tmp / mock helpers ----------------------------------------------------

make_tmp_dir() {
    local prefix="${1:-auto-dev-test}"
    local d
    d=$(mktemp -d -t "${prefix}.XXXXXX" 2>/dev/null || mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")
    register_cleanup "$d"
    printf '%s\n' "$d"
}

mock_bin_dir() {
    local d
    d=$(make_tmp_dir "auto-dev-bin")
    # When callers use BIN=$(mock_bin_dir) the export happens in a subshell
    # and cannot reach the parent. Record the dir in a channel file so
    # setup_mock_bin_dir can import it after the command substitution.
    if [ -n "${AUTO_DEV_MOCK_BIN_CHANNEL:-}" ]; then
        printf '%s' "$d" > "$AUTO_DEV_MOCK_BIN_CHANNEL"
    fi
    export PATH="${d}:${PATH}"
    printf '%s\n' "$d"
}

# setup_mock_bin_dir
# Creates the mock bin dir AND prepends it to PATH in the caller's shell.
# Prints the dir path on stdout (same contract as mock_bin_dir).
# Use this instead of `mock_bin_dir` when the caller captures output with $(...).
setup_mock_bin_dir() {
    AUTO_DEV_MOCK_BIN_CHANNEL=$(mktemp 2>/dev/null || echo "/tmp/mock-bin-channel-$$")
    export AUTO_DEV_MOCK_BIN_CHANNEL
    local d
    d=$(mock_bin_dir)
    if [ -s "$AUTO_DEV_MOCK_BIN_CHANNEL" ]; then
        d=$(cat "$AUTO_DEV_MOCK_BIN_CHANNEL")
    fi
    rm -f "$AUTO_DEV_MOCK_BIN_CHANNEL" 2>/dev/null || true
    unset AUTO_DEV_MOCK_BIN_CHANNEL
    export PATH="${d}:${PATH}"
    printf '%s\n' "$d"
}

install_stub() {
    local dir="$1" name="$2" body="$3"
    printf '%s\n' "$body" > "${dir}/${name}"
    chmod +x "${dir}/${name}"
}

mock_gh() {
    local dir="$1" exit_code="${2:-0}" stdout="${3:-}"
    install_stub "$dir" "gh" "#!/usr/bin/env bash
printf '%s' '${stdout//\'/\'\\\'\'}'
exit ${exit_code}
"
}

mock_docker() {
    local dir="$1" exit_code="${2:-0}" stdout="${3:-}"
    install_stub "$dir" "docker" "#!/usr/bin/env bash
printf '%s' '${stdout//\'/\'\\\'\'}'
exit ${exit_code}
"
}

# claude CLI の mock。exit_code と stdout_json を渡す。
# さらに呼出回数を ${MOCK_CLAUDE_CALL_LOG} にカウントする（任意）。
mock_claude() {
    local dir="$1" exit_code="${2:-0}" stdout_json="${3:-}"
    if [ -z "$stdout_json" ]; then
        stdout_json='{"result":"ok"}'
    fi
    local call_log="${MOCK_CLAUDE_CALL_LOG:-${dir}/claude-calls.log}"
    export MOCK_CLAUDE_CALL_LOG="$call_log"
    : > "$call_log"
    cat > "${dir}/claude" <<STUB
#!/usr/bin/env bash
# mock claude CLI for auto-dev tests
# Record one line per invocation (the full argv on a single line), so that
# \`wc -l < \$MOCK_CLAUDE_CALL_LOG\` yields the invocation count.
printf '%s\n' "\$*" >> "${call_log}"
printf '%s' '${stdout_json//\'/\'\\\'\'}'
exit ${exit_code}
STUB
    chmod +x "${dir}/claude"
}

# ---- 集計 ------------------------------------------------------------------

print_summary() {
    echo ""
    echo "================================"
    echo "  ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"
    if [ "${#FAILED_TESTS[@]}" -gt 0 ]; then
        echo "  Failed:"
        local t
        for t in "${FAILED_TESTS[@]}"; do
            echo "    - ${t}"
        done
    fi
    echo "================================"
    return "$TESTS_FAILED"
}

# process-issue.sh を source するテストで、親プロセスから継承した
# ISSUE_NUM が dispatcher を発火させる事故を防ぐための防御関数。
# Issue #159 F11 で導入（F9 の main() ラップと多重化）。
reset_auto_dev_env() {
    unset ISSUE_NUM AUTO_DEV_CURRENT_PHASE PHASE
}
