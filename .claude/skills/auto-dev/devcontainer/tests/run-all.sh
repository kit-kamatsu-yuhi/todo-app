#!/usr/bin/env bash
# run-all.sh — auto-dev tests ランナー（Issue #148 拡張版）
#
# 使い方:
#   bash .devcontainer/auto-dev/tests/run-all.sh
#
# 動作:
#   tests/test-*.sh を辞書順で順次実行し、PASS / FAIL を色付きで表示する。
#   test-helper.sh は対象外。
#   Issue #148 で追加された新規テスト群と、既存 test-failure-retry.sh /
#   test-merge-sync.sh / test-state.sh / test-dispatcher.sh / test-sync-main.sh /
#   test-crash-handling.sh を同居させる。
#   色は TTY で ANSI エスケープを出す。非 TTY では素で出す。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- カラー ---------------------------------------------------------------
if [ -t 1 ]; then
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_RESET=$'\033[0m'
else
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
    C_RESET=""
fi

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_NAMES=()

# 実行対象を抽出（test-helper.sh を除外）。bash 3.2 互換（mapfile 不使用）。
TEST_FILES=()
while IFS= read -r _line; do
    TEST_FILES+=("$_line")
done < <(
    find "$SCRIPT_DIR" -maxdepth 1 -type f -name 'test-*.sh' \
        ! -name 'test-helper.sh' \
        | sort
)

if [ "${#TEST_FILES[@]}" -eq 0 ]; then
    echo "${C_YELLOW}No test files found in ${SCRIPT_DIR}${C_RESET}"
    exit 0
fi

echo "${C_CYAN}Running ${#TEST_FILES[@]} test suite(s) from ${SCRIPT_DIR}${C_RESET}"
echo ""

for t in "${TEST_FILES[@]}"; do
    name=$(basename "$t")
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    echo "${C_CYAN}>>> ${name}${C_RESET}"
    if bash "$t"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
        echo "${C_GREEN}PASS${C_RESET}: ${name}"
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_NAMES+=("$name")
        echo "${C_RED}FAIL${C_RESET}: ${name}"
    fi
    echo ""
done

echo "================================================================"
echo "${C_CYAN}Suites: ${PASSED_SUITES}/${TOTAL_SUITES} passed, ${FAILED_SUITES} failed${C_RESET}"
if [ "${#FAILED_NAMES[@]}" -gt 0 ]; then
    echo "${C_RED}Failed suites:${C_RESET}"
    for n in "${FAILED_NAMES[@]}"; do
        echo "  - ${n}"
    done
fi
echo "================================================================"

if [ "$FAILED_SUITES" -gt 0 ]; then
    exit 1
fi
exit 0
