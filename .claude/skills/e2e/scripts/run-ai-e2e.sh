#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[ai-e2e] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*"
}

# stderr に出す log。command substitution に捕捉されたくない error 通知に使う。
log_err() {
  echo "[ai-e2e] $(date -u +"%Y-%m-%dT%H:%M:%SZ") $*" >&2
}

# Resolve absolute path to project root.
# Priority: E2E_PROJECT_ROOT env override > walk up from SCRIPT_DIR looking for
# a .claude/settings.json that is NOT under exoloop/.
# This handles symlinked layouts where ../../../.. lands inside exoloop/.
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"

resolve_project_root() {
  # 1. Explicit override wins.
  if [[ -n "${E2E_PROJECT_ROOT:-}" ]]; then
    if [[ ! -d "$E2E_PROJECT_ROOT" ]]; then
      log "ERROR: E2E_PROJECT_ROOT does not exist: $E2E_PROJECT_ROOT"
      exit 1
    fi
    (cd -P "$E2E_PROJECT_ROOT" && pwd)
    return 0
  fi

  # 2. Walk up from SCRIPT_DIR (which is already symlink-resolved via cd -P).
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -f "$dir/.claude/settings.json" ]]; then
      local base
      base="$(basename "$dir")"
      if [[ "$base" != "exoloop" ]]; then
        echo "$dir"
        return 0
      fi
    fi
    dir="$(dirname "$dir")"
  done

  log "ERROR: Could not locate project root (no .claude/settings.json outside exoloop/ found). Set E2E_PROJECT_ROOT to override."
  exit 1
}

ROOT_DIR="$(resolve_project_root)"
if [[ "$(basename "$ROOT_DIR")" == "exoloop" ]]; then
  log "ERROR: Resolved project root is exoloop/ (${ROOT_DIR}). Set E2E_PROJECT_ROOT to the consumer project root."
  exit 1
fi
cd "$ROOT_DIR"

SKILL_DIR=".claude/skills/e2e"
LOG_DIR="${SKILL_DIR}/_logs"

# Backend selection (agent-browser CLI or chrome-devtools MCP)
E2E_BACKEND="${E2E_BACKEND:-agent-browser}"

# Claude model: empty by default. When empty, fall through to Claude CLI default
# (so projects pin their own model via env without this script hardcoding one).
CLAUDE_MODEL="${CLAUDE_MODEL:-}"

is_ci() {
  [[ "${CI:-}" == "true" ]]
}

ensure_dir() {
  local dir="$1"
  mkdir -p "$dir"
}

resolve_cloud_region() {
  echo "${CLOUD_ML_REGION:-${GOOGLE_CLOUD_REGION:-global}}"
}

resolve_project_id() {
  echo "${ANTHROPIC_VERTEX_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
}

export_vertex_env() {
  local resolved_region resolved_project
  resolved_region="$(resolve_cloud_region)"
  resolved_project="$(resolve_project_id)"

  if [[ -n "$resolved_region" ]]; then
    export GOOGLE_CLOUD_REGION="$resolved_region"
  fi

  if [[ -n "$resolved_project" ]]; then
    export GOOGLE_CLOUD_PROJECT="$resolved_project"
  fi

  # Only build Vertex endpoint when we have project + region + model.
  if [[ -n "$resolved_project" && -n "$resolved_region" && -n "$CLAUDE_MODEL" ]]; then
    export VERTEX_AI_ENDPOINT="https://aiplatform.googleapis.com/v1/projects/${resolved_project}/locations/${resolved_region}/publishers/anthropic/models/${CLAUDE_MODEL}:streamGenerateContent"
    export CLAUDE_VERTEX_ENDPOINT="https://aiplatform.googleapis.com/v1/projects/${resolved_project}/locations/${resolved_region}/publishers/anthropic/models/${CLAUDE_MODEL}:streamGenerateContent"
  fi
}

CLAUDE_SETTINGS_BACKUP=""

restore_claude_settings() {
  if ! is_ci && [[ -n "$CLAUDE_SETTINGS_BACKUP" && -f "$CLAUDE_SETTINGS_BACKUP" ]]; then
    mv "$CLAUDE_SETTINGS_BACKUP" ".claude/settings.json" 2>/dev/null || true
    log "Restored original .claude/settings.json"
  fi
}

setup_claude_settings() {
  export_vertex_env

  local resolved_region resolved_project
  resolved_region="$(resolve_cloud_region)"
  resolved_project="$(resolve_project_id)"

  # Back up existing settings.json for local runs.
  if ! is_ci && [[ -f ".claude/settings.json" ]]; then
    CLAUDE_SETTINGS_BACKUP="$(mktemp)"
    cp ".claude/settings.json" "$CLAUDE_SETTINGS_BACKUP" 2>/dev/null || true
    trap restore_claude_settings EXIT
    trap 'restore_claude_settings; exit 130' INT
    trap 'restore_claude_settings; exit 143' TERM
    log "Backed up existing .claude/settings.json"
  fi

  if [[ ! -f ".claude/settings.json" ]]; then
    log "ERROR: .claude/settings.json not found. Please ensure settings.json exists."
    exit 1
  fi

  # Merge minimal E2E-required env into existing settings via node-jq.
  local merged_settings
  merged_settings=$(npx --yes node-jq \
    --arg project "$resolved_project" \
    --arg region "$resolved_region" \
    --arg model "$CLAUDE_MODEL" \
    '.env.ANTHROPIC_VERTEX_PROJECT_ID = $project |
    .env.CLOUD_ML_REGION = $region |
    (if $model == "" then . else .env.ANTHROPIC_MODEL = $model end) |
    .env.DISABLE_PROMPT_CACHING = "1" |
    .env.CLAUDE_CODE_USE_VERTEX = "1"' \
    ".claude/settings.json")
  echo "$merged_settings" > ".claude/settings.json"
  log "Merged E2E settings with existing configuration (project: ${resolved_project:-<unset>})"
}

select_env_file() {
  if is_ci; then
    echo "${SKILL_DIR}/.env.ci"
    return 0
  fi

  if [[ -f "${SKILL_DIR}/.env.local" ]]; then
    echo "${SKILL_DIR}/.env.local"
    return 0
  fi

  if [[ -f "${SKILL_DIR}/.env" ]]; then
    echo "${SKILL_DIR}/.env"
    return 0
  fi

  if [[ -f "${SKILL_DIR}/.env.ci" ]]; then
    echo "${SKILL_DIR}/.env.ci"
    return 0
  fi

  echo ""
}

load_e2e_env() {
  local env_file
  env_file="$(select_env_file)"

  if [[ -z "$env_file" ]]; then
    log "WARNING: No E2E environment file found. Copy ${SKILL_DIR}/.env.example to ${SKILL_DIR}/.env.local"
    return 0
  fi

  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
    if is_ci; then
      log "Loading CI environment from: $env_file"
    else
      log "Loading local environment from: $env_file"
    fi
  else
    log "WARNING: E2E environment file not found: $env_file"
  fi

  # In CI, allow GitHub Secrets / pipeline env to override credentials.
  if is_ci; then
    if [[ -n "${E2E_LOGIN_EMAIL:-}" ]]; then
      log "Using E2E_LOGIN_EMAIL from CI environment"
      export E2E_LOGIN_EMAIL="${E2E_LOGIN_EMAIL}"
    else
      log "WARNING: E2E_LOGIN_EMAIL not provided via CI environment"
    fi

    if [[ -n "${E2E_LOGIN_PASSWORD:-}" ]]; then
      log "Using login credentials from CI environment"
      export E2E_LOGIN_PASSWORD="${E2E_LOGIN_PASSWORD}"
    else
      log "WARNING: E2E_LOGIN_PASSWORD not provided via CI environment"
    fi
  fi
}

load_e2e_env

# Re-read after env load in case .env files set them.
E2E_BACKEND="${E2E_BACKEND:-agent-browser}"

# Validate backend selection. Accept only `agent-browser` or `chrome-devtools`
# (the real chrome-devtools MCP server name). The abstract `mcp` is no longer
# accepted, per PR #339 review feedback.
case "$E2E_BACKEND" in
  agent-browser|chrome-devtools) ;;
  *)
    log "ERROR: invalid E2E_BACKEND '${E2E_BACKEND}'. Expected 'agent-browser' or 'chrome-devtools'."
    exit 1
    ;;
esac

log "backend=${E2E_BACKEND}"

setup_claude_settings

# First positional argument acts as an optional scenario filter.
SCENARIO_FILTER="${1:-}"

# Validate scenario name to prevent prompt injection via the interpolation below.
if [[ -n "$SCENARIO_FILTER" ]]; then
  if ! [[ "$SCENARIO_FILTER" =~ ^[a-z0-9-]+$ ]]; then
    log "ERROR: scenario name must match [a-z0-9-]+"
    exit 1
  fi
fi

# Resolve GOOGLE_CLOUD_PROJECT for Vertex AI: env > gcloud default > warn.
if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
  if command -v gcloud >/dev/null 2>&1; then
    GCP_PROJECT_FROM_CONFIG="$(gcloud config get-value project 2>/dev/null || echo "")"
    if [[ -n "$GCP_PROJECT_FROM_CONFIG" && "$GCP_PROJECT_FROM_CONFIG" != "(unset)" ]]; then
      export GOOGLE_CLOUD_PROJECT="$GCP_PROJECT_FROM_CONFIG"
      log "GOOGLE_CLOUD_PROJECT resolved from gcloud config: $GOOGLE_CLOUD_PROJECT"
    fi
  fi
fi

if [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
  log "WARNING: GOOGLE_CLOUD_PROJECT not set and no gcloud default — Vertex AI calls will fail"
fi

# Verify Google Cloud authentication when GOOGLE_CLOUD_PROJECT is known and we're not in CI.
if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]] && ! is_ci; then
  if command -v gcloud >/dev/null 2>&1; then
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
      log "WARNING: Google Cloud authentication not configured or expired"
      log "If using Vertex, run: gcloud auth application-default login --project=${GOOGLE_CLOUD_PROJECT}"
    fi

    if [[ -f ~/.config/gcloud/application_default_credentials.json ]]; then
      adc_project=$(grep -o '"project_id":"[^"]*"' ~/.config/gcloud/application_default_credentials.json 2>/dev/null | cut -d'"' -f4 || echo "unknown")
      if [[ "$adc_project" != "${GOOGLE_CLOUD_PROJECT}" ]]; then
        log "WARNING: ADC project ($adc_project) does not match GOOGLE_CLOUD_PROJECT ($GOOGLE_CLOUD_PROJECT)"
      fi
    fi
  fi
fi

ensure_dir "$LOG_DIR"

# Build skill execution prompt. The e2e skill itself decides backend dispatch.
if [[ -n "$SCENARIO_FILTER" ]]; then
  log "Running e2e skill with scenario filter: $SCENARIO_FILTER (backend=${E2E_BACKEND})"
  SKILL_PROMPT="run \"/e2e backend=${E2E_BACKEND} scenario=${SCENARIO_FILTER}\""
else
  log "Running e2e skill against all scenarios (backend=${E2E_BACKEND})"
  SKILL_PROMPT="run \"/e2e backend=${E2E_BACKEND}\""
fi

log "Executing: $SKILL_PROMPT"
if [[ -n "$CLAUDE_MODEL" ]]; then
  log "Model: $CLAUDE_MODEL"
else
  log "Model: <Claude CLI default>"
fi

# detect_runner: pick which AI runner CLI to drive the skill prompt with.
# Priority: claude-code (binary or npx) → codex CLI → antigravity CLI.
# Honors E2E_RUNNER env override (one of: claude, codex, antigravity).
# Emits two lines on stdout: "<runner>\n<invocation_path>".
#   - claude binary: "claude\n<path-to-claude-binary>"
#   - claude via npx: "claude\nnpx"
#   - codex:         "codex\n<path-to-codex>"
#   - antigravity:   "antigravity\n<path-to-antigravity>"
detect_runner() {
  local override="${E2E_RUNNER:-}"

  # has_claude_binary: prefer `claude-code`, fall back to `claude` (Anthropic ships either).
  local claude_bin=""
  if command -v claude-code >/dev/null 2>&1; then
    claude_bin="$(command -v claude-code)"
  elif command -v claude >/dev/null 2>&1; then
    claude_bin="$(command -v claude)"
  fi

  # npx availability — used as a claude fallback (legacy behaviour).
  local has_npx=0
  if command -v npx >/dev/null 2>&1; then
    has_npx=1
  fi

  local has_codex=0
  local codex_bin=""
  if command -v codex >/dev/null 2>&1; then
    has_codex=1
    codex_bin="$(command -v codex)"
  fi

  local has_antigravity=0
  local antigravity_bin=""
  if command -v antigravity >/dev/null 2>&1; then
    has_antigravity=1
    antigravity_bin="$(command -v antigravity)"
  fi

  if [[ -n "$override" ]]; then
    case "$override" in
      claude)
        if [[ -n "$claude_bin" ]]; then
          printf '%s\n%s\n' "claude" "$claude_bin"
          return 0
        elif [[ $has_npx -eq 1 ]]; then
          printf '%s\n%s\n' "claude" "npx"
          return 0
        fi
        log_err "ERROR: E2E_RUNNER=claude requested but no claude-code/claude binary and no npx found."
        return 1
        ;;
      codex)
        if [[ $has_codex -eq 1 ]]; then
          printf '%s\n%s\n' "codex" "$codex_bin"
          return 0
        fi
        log_err "ERROR: E2E_RUNNER=codex requested but codex CLI not found on PATH."
        return 1
        ;;
      antigravity)
        if [[ $has_antigravity -eq 1 ]]; then
          printf '%s\n%s\n' "antigravity" "$antigravity_bin"
          return 0
        fi
        log_err "ERROR: E2E_RUNNER=antigravity requested but antigravity CLI not found on PATH."
        return 1
        ;;
      *)
        log_err "ERROR: invalid E2E_RUNNER '${override}'. Expected one of: claude, codex, antigravity."
        return 1
        ;;
    esac
  fi

  # Auto-detect order: claude (binary) → claude (npx fallback) → codex → antigravity。
  # Node が入っている環境では npx が常に解決するため、codex/antigravity を強制したい場合は
  # E2E_RUNNER=codex / E2E_RUNNER=antigravity を指定する。
  if [[ -n "$claude_bin" ]]; then
    printf '%s\n%s\n' "claude" "$claude_bin"
    return 0
  fi
  if [[ $has_npx -eq 1 ]]; then
    printf '%s\n%s\n' "claude" "npx"
    return 0
  fi
  if [[ $has_codex -eq 1 ]]; then
    printf '%s\n%s\n' "codex" "$codex_bin"
    return 0
  fi
  if [[ $has_antigravity -eq 1 ]]; then
    printf '%s\n%s\n' "antigravity" "$antigravity_bin"
    return 0
  fi

  log_err "ERROR: No AI runner CLI found. Install one of: claude-code (npm install -g @anthropic-ai/claude-code), codex CLI, or antigravity CLI."
  return 1
}

RUNNER_OUTPUT="$(detect_runner)" || exit 1
RUNNER_NAME="$(echo "$RUNNER_OUTPUT" | sed -n '1p')"
RUNNER_PATH="$(echo "$RUNNER_OUTPUT" | sed -n '2p')"
log "runner=${RUNNER_NAME} path=${RUNNER_PATH}"

set +e
case "$RUNNER_NAME" in
  claude)
    if [[ "$RUNNER_PATH" == "npx" ]]; then
      if [[ -n "$CLAUDE_MODEL" ]]; then
        npx @anthropic-ai/claude-code \
          --model "${CLAUDE_MODEL}" \
          --dangerously-skip-permissions \
          -- \
          "$SKILL_PROMPT"
      else
        npx @anthropic-ai/claude-code \
          --dangerously-skip-permissions \
          -- \
          "$SKILL_PROMPT"
      fi
    else
      if [[ -n "$CLAUDE_MODEL" ]]; then
        "$RUNNER_PATH" \
          --model "${CLAUDE_MODEL}" \
          --dangerously-skip-permissions \
          -- \
          "$SKILL_PROMPT"
      else
        "$RUNNER_PATH" \
          --dangerously-skip-permissions \
          -- \
          "$SKILL_PROMPT"
      fi
    fi
    ;;
  codex)
    # codex CLI: invoke non-interactive `exec` subcommand with the prompt.
    # If codex CLI changes its invocation surface, update this line.
    "$RUNNER_PATH" exec "$SKILL_PROMPT"
    ;;
  antigravity)
    # antigravity CLI: tentative invocation — `antigravity run "<prompt>"`.
    # The antigravity CLI surface is not yet stabilized; revisit if it changes.
    "$RUNNER_PATH" run "$SKILL_PROMPT"
    ;;
esac
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -ne 0 ]]; then
  log "ERROR: e2e skill execution failed (exit code: ${EXIT_CODE})"
  exit $EXIT_CODE
fi

log "e2e skill execution completed successfully"
exit 0
