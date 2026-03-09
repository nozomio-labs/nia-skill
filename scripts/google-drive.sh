#!/usr/bin/env bash
# Nia Google Drive — installation management and Drive indexing
# Usage: google-drive.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── install — generate a Google Drive OAuth authorization URL
cmd_install() {
  DATA=$(jq -n --arg redirect "${1:-${REDIRECT_URI:-}}" --arg scopes "${SCOPES:-}" \
    '{}
    + (if $redirect != "" then {redirect_uri: $redirect} else {} end)
    + (if $scopes != "" then {scopes: ($scopes | split(","))} else {} end)')
  nia_post "$BASE_URL/google-drive/install" "$DATA"
}

# ─── callback — exchange OAuth code for tokens and create the installation
cmd_callback() {
  if [ -z "$1" ]; then
    echo "Usage: google-drive.sh callback <code> [redirect_uri]"
    return 1
  fi
  DATA=$(jq -n --arg code "$1" --arg redirect "${2:-${REDIRECT_URI:-}}" \
    '{code: $code}
    + (if $redirect != "" then {redirect_uri: $redirect} else {} end)')
  nia_post "$BASE_URL/google-drive/install/callback" "$DATA"
}

# ─── list — list all Google Drive installations
cmd_list() {
  nia_get "$BASE_URL/google-drive/installations"
}

# ─── get — get details for a specific Google Drive installation
cmd_get() {
  if [ -z "$1" ]; then echo "Usage: google-drive.sh get <installation_id>"; return 1; fi
  nia_get "$BASE_URL/google-drive/installations/$1"
}

# ─── delete — disconnect a Google Drive installation
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: google-drive.sh delete <installation_id>"; return 1; fi
  nia_delete "$BASE_URL/google-drive/installations/$1"
}

# ─── browse — browse Drive files/folders before selecting what to index
cmd_browse() {
  if [ -z "$1" ]; then
    echo "Usage: google-drive.sh browse <installation_id> [folder_id] [query] [page_token] [page_size]"
    return 1
  fi
  local installation_id="$1"
  local folder_id="${2:-}"
  local query="${3:-}"
  local page_token="${4:-}"
  local page_size="${5:-${PAGE_SIZE:-100}}"
  local url="$BASE_URL/google-drive/installations/${installation_id}/browse?page_size=${page_size}"
  if [ -n "$folder_id" ]; then url="${url}&folder_id=$(echo "$folder_id" | jq -Rr @uri)"; fi
  if [ -n "$query" ]; then url="${url}&q=$(echo "$query" | jq -Rr @uri)"; fi
  if [ -n "$page_token" ]; then url="${url}&page_token=$(echo "$page_token" | jq -Rr @uri)"; fi
  nia_get "$url"
}

# ─── index — trigger Drive indexing for explicit file/folder IDs
cmd_index() {
  if [ -z "$1" ]; then
    echo "Usage: google-drive.sh index <installation_id> [file_ids_csv] [folder_ids_csv] [display_name]"
    echo "  Env: FILE_IDS, FOLDER_IDS, DISPLAY_NAME"
    return 1
  fi
  local file_ids_csv="${2:-${FILE_IDS:-}}"
  local folder_ids_csv="${3:-${FOLDER_IDS:-}}"
  local display_name="${4:-${DISPLAY_NAME:-}}"
  DATA=$(jq -n \
    --arg f "$file_ids_csv" --arg d "$folder_ids_csv" --arg n "$display_name" \
    '{} + (if $f != "" then {file_ids: ($f | split(","))} else {} end)
       + (if $d != "" then {folder_ids: ($d | split(","))} else {} end)
       + (if $n != "" then {display_name: $n} else {} end)')
  nia_post "$BASE_URL/google-drive/installations/$1/index" "$DATA"
}

# ─── selection — fetch the current selected Drive scope
cmd_selection() {
  if [ -z "$1" ]; then echo "Usage: google-drive.sh selection <installation_id>"; return 1; fi
  nia_get "$BASE_URL/google-drive/installations/$1/selection"
}

# ─── update-selection — replace the Drive selection with file/folder IDs
cmd_update_selection() {
  if [ -z "$1" ] || [ -z "${2:-${ITEM_IDS:-}}" ]; then
    echo "Usage: google-drive.sh update-selection <installation_id> <item_ids_csv> [display_name]"
    echo "  Env: ITEM_IDS, DISPLAY_NAME"
    return 1
  fi
  local item_ids_csv="${2:-${ITEM_IDS:-}}"
  local display_name="${3:-${DISPLAY_NAME:-}}"
  DATA=$(jq -n --arg ids "$item_ids_csv" --arg n "$display_name" \
    '{item_ids: ($ids | split(","))}
    + (if $n != "" then {display_name: $n} else {} end)')
  nia_post "$BASE_URL/google-drive/installations/$1/selection" "$DATA"
}

# ─── status — get Drive indexing/sync status
cmd_status() {
  if [ -z "$1" ]; then echo "Usage: google-drive.sh status <installation_id>"; return 1; fi
  nia_get "$BASE_URL/google-drive/installations/$1/status"
}

# ─── sync — trigger incremental or full sync for an installation
cmd_sync() {
  if [ -z "$1" ]; then
    echo "Usage: google-drive.sh sync <installation_id> [scope_ids_csv]"
    echo "  Env: FORCE_FULL=true"
    return 1
  fi
  local scope_ids_csv="${2:-${SCOPE_IDS:-}}"
  DATA=$(jq -n --arg scopes "$scope_ids_csv" --arg full "${FORCE_FULL:-}" \
    '{} + (if $full != "" then {force_full: ($full == "true")} else {} end)
       + (if $scopes != "" then {scope_ids: ($scopes | split(","))} else {} end)')
  nia_post "$BASE_URL/google-drive/installations/$1/sync" "$DATA"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  install)           shift; cmd_install "$@" ;;
  callback)          shift; cmd_callback "$@" ;;
  list)              shift; cmd_list "$@" ;;
  get)               shift; cmd_get "$@" ;;
  delete)            shift; cmd_delete "$@" ;;
  browse)            shift; cmd_browse "$@" ;;
  index)             shift; cmd_index "$@" ;;
  selection)         shift; cmd_selection "$@" ;;
  update-selection)  shift; cmd_update_selection "$@" ;;
  status)            shift; cmd_status "$@" ;;
  sync)              shift; cmd_sync "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  install           Generate Google Drive OAuth URL"
    echo "  callback          Exchange OAuth code for tokens"
    echo "  list              List Google Drive installations"
    echo "  get               Get installation details"
    echo "  delete            Disconnect installation"
    echo "  browse            Browse Drive files/folders"
    echo "  index             Trigger indexing for file/folder IDs"
    echo "  selection         Get current Drive selection"
    echo "  update-selection  Update selected Drive items"
    echo "  status            Get indexing/sync status"
    echo "  sync              Trigger incremental/full sync"
    exit 1
    ;;
esac

