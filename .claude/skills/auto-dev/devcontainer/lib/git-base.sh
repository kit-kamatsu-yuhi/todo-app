#!/bin/bash
# Resolve the upstream default branch (e.g. main, master) for a cloned repo.
#
# Reads `git symbolic-ref refs/remotes/origin/HEAD`. If origin/HEAD is missing
# (older clones, or remotes that never published HEAD), tries
# `git remote set-head origin --auto` once and re-reads. Falls back to "main"
# only as a last resort so a misconfigured repo still moves forward.
#
# Usage:
#   source "${LIB_DIR}/git-base.sh"
#   BASE_BRANCH=$(detect_base_branch "$REPO_DIR")

detect_base_branch() {
    local repo_dir="${1:-${REPO_DIR:-/workspace/repo}}"
    local ref
    ref=$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || ref=""
    if [ -z "$ref" ]; then
        git -C "$repo_dir" remote set-head origin --auto >/dev/null 2>&1 || true
        ref=$(git -C "$repo_dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || ref=""
    fi
    if [ -n "$ref" ]; then
        printf '%s' "${ref#origin/}"
    else
        printf 'main'
    fi
}
