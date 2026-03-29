#!/usr/bin/env bash
# Nia X (Twitter) — index and search X/Twitter posts
# Usage: x.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── create — create an X installation to index a user's posts
cmd_create() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: x.sh create <username> <bearer_token> [display_name]"
    echo "  Env: MAX_RESULTS (1-500, default 100), INCLUDE_REPLIES, INCLUDE_RETWEETS"
    return 1
  fi
  DATA=$(jq -n \
    --arg user "$1" --arg token "$2" --arg dn "${3:-${DISPLAY_NAME:-}}" \
    --arg max "${MAX_RESULTS:-}" --arg replies "${INCLUDE_REPLIES:-}" \
    --arg retweets "${INCLUDE_RETWEETS:-}" \
    '{username: $user, bearer_token: $token}
    + (if $dn != "" then {display_name: $dn} else {} end)
    + (if $max != "" then {max_results: ($max | tonumber)} else {} end)
    + (if $replies != "" then {include_replies: ($replies == "true")} else {} end)
    + (if $retweets != "" then {include_retweets: ($retweets == "true")} else {} end)')
  nia_post "$BASE_URL/x/installations" "$DATA"
}

# ─── list — list all X installations
cmd_list() {
  nia_get "$BASE_URL/x/installations"
}

# ─── get — get details for a specific X installation
cmd_get() {
  if [ -z "$1" ]; then echo "Usage: x.sh get <installation_id>"; return 1; fi
  nia_get "$BASE_URL/x/installations/$1"
}

# ─── delete — remove an X installation
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: x.sh delete <installation_id>"; return 1; fi
  nia_delete "$BASE_URL/x/installations/$1"
}

# ─── index — trigger indexing for an X installation
cmd_index() {
  if [ -z "$1" ]; then echo "Usage: x.sh index <installation_id>"; return 1; fi
  nia_post "$BASE_URL/x/installations/$1/index" "{}"
}

# ─── status — get the indexing status for an X installation
cmd_status() {
  if [ -z "$1" ]; then echo "Usage: x.sh status <installation_id>"; return 1; fi
  nia_get "$BASE_URL/x/installations/$1/status"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  create) shift; cmd_create "$@" ;;
  list)   shift; cmd_list "$@" ;;
  get)    shift; cmd_get "$@" ;;
  delete) shift; cmd_delete "$@" ;;
  index)  shift; cmd_index "$@" ;;
  status) shift; cmd_status "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "X (Twitter) post indexing and search."
    echo ""
    echo "Commands:"
    echo "  create   Create X installation (index a user's posts)"
    echo "  list     List X installations"
    echo "  get      Get installation details"
    echo "  delete   Remove X installation"
    echo "  index    Trigger re-index"
    echo "  status   Get indexing status"
    exit 1
    ;;
esac
