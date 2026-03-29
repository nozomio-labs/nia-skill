#!/usr/bin/env bash
# Nia Extract — structured data extraction from documents
# Usage: extract.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── start — start a table extraction with a JSON schema
cmd_start() {
  if [ -z "$1" ]; then
    echo "Usage: extract.sh start <json_schema_file_or_string>"
    echo "  Env: URL (document URL), SOURCE_ID, PAGE_RANGE (e.g. '1-5')"
    return 1
  fi
  local schema
  if [ -f "$1" ]; then
    schema=$(cat "$1")
  else
    schema="$1"
  fi
  DATA=$(jq -n \
    --argjson schema "$schema" \
    --arg url "${URL:-}" --arg sid "${SOURCE_ID:-}" --arg pages "${PAGE_RANGE:-}" \
    '{json_schema: $schema}
    + (if $url != "" then {url: $url} else {} end)
    + (if $sid != "" then {source_id: $sid} else {} end)
    + (if $pages != "" then {page_range: $pages} else {} end)')
  nia_post "$BASE_URL/extract" "$DATA"
}

# ─── get — get extraction status and results
cmd_get() {
  if [ -z "$1" ]; then echo "Usage: extract.sh get <extraction_id>"; return 1; fi
  nia_get "$BASE_URL/extract/$1"
}

# ─── engineering — start an engineering extraction
cmd_engineering() {
  if [ -z "${URL:-}${SOURCE_ID:-}" ]; then
    echo "Usage: extract.sh engineering"
    echo "  Env: URL (document URL) or SOURCE_ID, PAGE_RANGE, ACCURACY_MODE (fast|accurate)"
    return 1
  fi
  DATA=$(jq -n \
    --arg url "${URL:-}" --arg sid "${SOURCE_ID:-}" \
    --arg pages "${PAGE_RANGE:-}" --arg mode "${ACCURACY_MODE:-fast}" \
    '{accuracy_mode: $mode}
    + (if $url != "" then {url: $url} else {} end)
    + (if $sid != "" then {source_id: $sid} else {} end)
    + (if $pages != "" then {page_range: $pages} else {} end)')
  nia_post "$BASE_URL/extract/engineering" "$DATA"
}

# ─── engineering-get — get engineering extraction status and results
cmd_engineering_get() {
  if [ -z "$1" ]; then echo "Usage: extract.sh engineering-get <extraction_id>"; return 1; fi
  nia_get "$BASE_URL/extract/engineering/$1"
}

# ─── engineering-query — query an engineering extraction
cmd_engineering_query() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: extract.sh engineering-query <extraction_id> <query>"
    return 1
  fi
  DATA=$(jq -n --arg q "$2" '{query: $q}')
  nia_post "$BASE_URL/extract/engineering/$1/query" "$DATA"
}

# ─── list — list all extractions
cmd_list() {
  local url="$BASE_URL/extractions" sep="?"
  if [ -n "${EXTRACT_TYPE:-}" ]; then url="${url}${sep}type=${EXTRACT_TYPE}"; sep="&"; fi
  if [ -n "${1:-}" ]; then url="${url}${sep}limit=$1"; sep="&"; fi
  if [ -n "${2:-}" ]; then url="${url}${sep}offset=$2"; fi
  nia_get "$url"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  start)             shift; cmd_start "$@" ;;
  get)               shift; cmd_get "$@" ;;
  engineering)       shift; cmd_engineering "$@" ;;
  engineering-get)   shift; cmd_engineering_get "$@" ;;
  engineering-query) shift; cmd_engineering_query "$@" ;;
  list)              shift; cmd_list "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Structured data extraction from documents."
    echo ""
    echo "Commands:"
    echo "  start              Start table extraction with JSON schema"
    echo "  get                Get extraction status/results"
    echo "  engineering        Start engineering extraction"
    echo "  engineering-get    Get engineering extraction status/results"
    echo "  engineering-query  Query an engineering extraction"
    echo "  list               List all extractions [limit] [offset]"
    echo ""
    echo "Env: EXTRACT_TYPE (table|engineering) for list filtering"
    exit 1
    ;;
esac
