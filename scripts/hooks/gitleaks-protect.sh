#!/usr/bin/env bash
# gitleaks-protect.sh — pre-commit の secret 検査ラッパー
#
# exoloop / gitleaks skill のフォールバック仕様に準拠する:
#   1. GITLEAKS_ENABLE=0 が指定されていれば検査を skip (exit 0)
#   2. gitleaks が PATH に無ければ WARN して通す (exit 0)
#   3. それ以外は staged diff を検査する
#      （.gitleaks.toml があれば --config に渡す。無ければ gitleaks 内蔵ルールで検査）
#
# 一時的に検査を skip したい場合:
#   GITLEAKS_ENABLE=0 git commit ...
set -uo pipefail

if [ "${GITLEAKS_ENABLE:-1}" = "0" ]; then
  echo "[gitleaks] GITLEAKS_ENABLE=0 のため secret 検査を skip します"
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[gitleaks] WARN: gitleaks が見つかりません。secret 検査を skip します。" >&2
  echo "          install: brew install gitleaks / https://github.com/gitleaks/gitleaks/releases" >&2
  exit 0
fi

CONFIG_ARGS=()
if [ -f .gitleaks.toml ]; then
  CONFIG_ARGS=(--config .gitleaks.toml)
fi

exec gitleaks protect --staged --redact "${CONFIG_ARGS[@]}"
