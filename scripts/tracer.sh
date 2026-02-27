#!/usr/bin/env bash
# Nia Tracer — autonomous GitHub code search agent
# Usage: tracer.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# helper: normalize user-friendly mode aliases
_normalize_tracer_mode() {
  local mode="${1:-}"
  case "$mode" in
    "") echo "" ;;
    fast|tracer-fast) echo "tracer-fast" ;;
    slow|deep|tracer-deep) echo "tracer-deep" ;;
    *) return 1 ;;
  esac
}

# helper: build tracer body with query, repos, context, mode
_tracer_body() {
  local query="$1" repos="${2:-}" context="${3:-}" mode="${4:-}"
  DATA=$(jq -n --arg q "$query" '{query: $q}')
  if [ -n "$repos" ]; then DATA=$(echo "$DATA" | jq --arg r "$repos" '. + {repositories: ($r | split(","))}'); fi
  if [ -n "$context" ]; then DATA=$(echo "$DATA" | jq --arg c "$context" '. + {context: $c}'); fi
  if [ -n "$mode" ]; then DATA=$(echo "$DATA" | jq --arg t "$mode" '. + {mode: $t}'); fi
  if [ -n "${MODEL:-}" ]; then DATA=$(echo "$DATA" | jq --arg m "$MODEL" '. + {model: $m}'); fi
  echo "$DATA"
}

# ─── run — create a Tracer job and return job_id
cmd_run() {
  if [ -z "$1" ]; then
    echo "Usage: tracer.sh run <query> [repos_csv] [context] [mode]"
    echo "  Creates a Tracer job to search GitHub repositories"
    echo "  mode: fast|slow (aliases: tracer-fast|tracer-deep)"
    echo "  Env: MODEL (claude-opus-4-6|claude-opus-4-6-1m|claude-haiku-4-5-20251001), TRACER_MODE (fast|slow)"
    echo ""
    echo "Examples:"
    echo "  tracer.sh run 'How does streaming work?' vercel/ai fast"
    echo "  tracer.sh run 'How does useEffect cleanup work?' facebook/react 'Focus on the hooks implementation' slow"
    return 1
  fi

  local query="$1"
  local repos="${2:-}"
  local context="${3:-}"
  local mode_input="${4:-}"

  # If context looks like a mode alias and no explicit 4th arg is given,
  # treat it as mode for backward-friendly convenience.
  if [ -z "$mode_input" ] && [ -n "$context" ]; then
    if _normalize_tracer_mode "$context" >/dev/null 2>&1; then
      mode_input="$context"
      context=""
    fi
  fi

  if [ -z "$mode_input" ] && [ -n "${TRACER_MODE:-}" ]; then
    mode_input="$TRACER_MODE"
  fi

  local mode=""
  if [ -n "$mode_input" ]; then
    if ! mode=$(_normalize_tracer_mode "$mode_input"); then
      echo "Invalid tracer mode: '$mode_input'"
      echo "Use: fast | slow | tracer-fast | tracer-deep"
      return 1
    fi
  fi

  DATA=$(_tracer_body "$query" "$repos" "$context" "$mode")
  nia_post "$BASE_URL/github/tracer" "$DATA"
}

# ─── status — get job status and result
cmd_status() {
  if [ -z "$1" ]; then echo "Usage: tracer.sh status <job_id>"; return 1; fi
  nia_get "$BASE_URL/github/tracer/$1"
}

# ─── stream — stream real-time updates from a running job (SSE)
cmd_stream() {
  if [ -z "$1" ]; then echo "Usage: tracer.sh stream <job_id>"; return 1; fi
  curl -s -N "$BASE_URL/github/tracer/$1/stream" -H "Authorization: Bearer $NIA_KEY"
}

# ─── list — list Tracer jobs
cmd_list() {
  local status="${1:-}" limit="${2:-50}"
  local url="$BASE_URL/github/tracer?limit=$limit"
  if [ -n "$status" ]; then url="$url&status=$status"; fi
  nia_get "$url"
}

# ─── delete — delete a Tracer job
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: tracer.sh delete <job_id>"; return 1; fi
  nia_delete "$BASE_URL/github/tracer/$1"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  run)     shift; cmd_run "$@" ;;
  status)  shift; cmd_status "$@" ;;
  stream)  shift; cmd_stream "$@" ;;
  list)    shift; cmd_list "$@" ;;
  delete)  shift; cmd_delete "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Tracer is an autonomous agent that searches GitHub repositories"
    echo "to answer questions. Powered by Claude Opus 4.6 with 1M context."
    echo ""
    echo "Commands:"
    echo "  run      Create a Tracer job [query] [repos_csv] [context] [mode]"
    echo "  status   Get job status/result"
    echo "  stream   Stream real-time updates (SSE)"
    echo "  list     List jobs [status] [limit]"
    echo "  delete   Delete a job"
    echo ""
    echo "Modes: fast | slow (aliases: tracer-fast | tracer-deep)"
    echo ""
    echo "Example workflow:"
    echo "  1. tracer.sh run 'How does auth work?' owner/repo slow"
    echo "  2. tracer.sh stream <job_id>   # watch progress"
    echo "  3. tracer.sh status <job_id>   # get final result"
    exit 1
    ;;
esac
