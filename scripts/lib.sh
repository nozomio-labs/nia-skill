#!/usr/bin/env bash
# Shared library for Nia API scripts
# Source this file: source "$(dirname "$0")/lib.sh"

BASE_URL="https://apigcp.trynia.ai/v2"
NIA_CONNECT_TIMEOUT_SECONDS="${NIA_CONNECT_TIMEOUT_SECONDS:-10}"
NIA_TIMEOUT_SECONDS="${NIA_TIMEOUT_SECONDS:-90}"

nia_auth() {
  if [ -n "${NIA_API_KEY:-}" ]; then
    NIA_KEY="$NIA_API_KEY"
  else
    NIA_KEY=$(cat ~/.config/nia/api_key 2>/dev/null || echo "")
  fi
  if [ -z "$NIA_KEY" ]; then
    echo "Error: No API key found. Set NIA_API_KEY env variable or run: echo 'your-key' > ~/.config/nia/api_key"
    exit 1
  fi
  export NIA_KEY
}

urlencode() {
  echo "$1" | sed 's/ /%20/g; s/\//%2F/g'
}

nia_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

nia_is_source_id() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-fA-F]{24}$ ]] || [[ "$value" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

nia_source_status_label() {
  local source_json="$1"
  echo "$source_json" | jq -r '
    if (.status // empty) != "" then .status
    elif (.index_status // empty) != "" then .index_status
    elif (.metadata.index_status // empty) != "" then .metadata.index_status
    elif (.metadata.status // empty) != "" then .metadata.status
    elif (.is_indexed == true or .metadata.is_indexed == true) then "indexed"
    elif (.is_indexed == false or .metadata.is_indexed == false) then "not_indexed"
    else "unknown"
    end
  ' 2>/dev/null
}

nia_source_is_ready() {
  local source_json="$1"
  local explicit indexed_status
  explicit=$(echo "$source_json" | jq -r '
    if (.is_indexed == true or .metadata.is_indexed == true) then "true"
    elif (.is_indexed == false or .metadata.is_indexed == false) then "false"
    else ""
    end
  ' 2>/dev/null)
  if [ "$explicit" = "true" ]; then
    return 0
  fi
  indexed_status=$(echo "$source_json" | jq -r '(.status // .index_status // .metadata.index_status // .metadata.status // "") | tostring | ascii_downcase' 2>/dev/null)
  case "$indexed_status" in
    ""|indexed|ready|complete|completed|synced|success|active)
      [ "$explicit" = "false" ] && return 1
      return 0
      ;;
    indexing|processing|pending|queued|in_progress|running|syncing|building|not_indexed|failed|error|deleted|deleting)
      return 1
      ;;
    *)
      [ "$explicit" = "false" ] && return 1
      return 0
      ;;
  esac
}

# Generic curl wrapper: nia_curl METHOD URL [DATA]
# Captures HTTP status code and returns JSON. Non-JSON errors (e.g. rate limits) are wrapped.
nia_curl() {
  local method="$1" url="$2" data="${3:-}"
  local args=(-s --connect-timeout "$NIA_CONNECT_TIMEOUT_SECONDS" --max-time "$NIA_TIMEOUT_SECONDS" -w '\n__HTTP_STATUS:%{http_code}' -X "$method" "$url" -H "Authorization: Bearer $NIA_KEY")
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi
  local response curl_exit
  set +e
  response=$(curl "${args[@]}" 2>/dev/null)
  curl_exit=$?
  set -e
  if [ "$curl_exit" -ne 0 ]; then
    local msg
    case "$curl_exit" in
      28) msg="Request timed out after ${NIA_TIMEOUT_SECONDS}s. Increase NIA_TIMEOUT_SECONDS if needed." ;;
      7) msg="Failed to connect to Nia API. Check network access and BASE_URL." ;;
      *) msg="Request failed with curl exit code ${curl_exit}." ;;
    esac
    jq -n --arg msg "$msg" --argjson code 0 --argjson cexit "$curl_exit" '{error: $msg, http_status: $code, curl_exit: $cexit}' 2>/dev/null \
      || printf '{"error":"request failed","http_status":0,"curl_exit":%d}\n' "$curl_exit"
    return 0
  fi
  local http_status="${response##*__HTTP_STATUS:}"
  local body="${response%__HTTP_STATUS:*}"
  http_status="${http_status//[!0-9]/}"
  : "${http_status:=0}"
  if echo "$body" | jq '.' >/dev/null 2>&1; then
    echo "$body"
  else
    jq -n --arg msg "$body" --argjson code "$http_status" '{error: $msg, http_status: $code}' 2>/dev/null \
      || printf '{"error":"request failed","http_status":%d}\n' "$http_status"
  fi
}

nia_get()    { nia_curl GET    "$1" | jq '.'; }
nia_post()   { nia_curl POST   "$1" "$2" | jq '.'; }
nia_put()    { nia_curl PUT    "$1" "$2" | jq '.'; }
nia_patch()  { nia_curl PATCH  "$1" "$2" | jq '.'; }
nia_delete() { nia_curl DELETE "$1" | jq '.'; }

# Raw get with custom jq filter: nia_get_raw URL | jq ...
nia_get_raw() { nia_curl GET "$1"; }
nia_post_raw() { nia_curl POST "$1" "$2"; }

# Stream (SSE) — no buffering, no jq
nia_stream() { curl -s -N -X POST "$1" -H "Authorization: Bearer $NIA_KEY" -H "Content-Type: application/json" -d "$2"; }

# Form upload: nia_upload URL field1=val1 field2=val2 file=@path
nia_upload() {
  local url="$1"; shift
  local args=(-s -X POST "$url" -H "Authorization: Bearer $NIA_KEY")
  for f in "$@"; do args+=(-F "$f"); done
  curl "${args[@]}" | jq '.'
}

# Resolve a human-friendly identifier (owner/repo, URL, display name) to a source ID.
# Returns the resolved ID, or the original value if it's already a UUID/ObjectId.
resolve_source_id() {
  local identifier="$1" type="${2:-}"
  if [[ "$identifier" =~ ^[0-9a-fA-F]{24}$ ]] || [[ "$identifier" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    echo "$identifier"
    return 0
  fi
  local encoded=$(urlencode "$identifier")
  local url="$BASE_URL/sources/resolve?identifier=${encoded}"
  if [ -n "$type" ]; then url="${url}&type=${type}"; fi
  local result
  result=$(nia_curl GET "$url")
  local resolved_id=$(echo "$result" | jq -r '.id // empty' 2>/dev/null)
  if [ -n "$resolved_id" ]; then
    echo "$resolved_id"
    return 0
  fi
  echo "$identifier"
  return 1
}

# Helper: build grep JSON body with all common options
build_grep_json() {
  local pattern="$1" path_prefix="${2:-}"
  jq -n \
    --arg p "$pattern" \
    --arg pp "$path_prefix" \
    --arg cs "${CASE_SENSITIVE:-}" \
    --arg ww "${WHOLE_WORD:-}" \
    --arg fs "${FIXED_STRING:-}" \
    --arg om "${OUTPUT_MODE:-}" \
    --arg hl "${HIGHLIGHT:-}" \
    --arg ex "${EXHAUSTIVE:-}" \
    --arg la "${LINES_AFTER:-}" \
    --arg lb "${LINES_BEFORE:-}" \
    --arg mpf "${MAX_PER_FILE:-}" \
    --arg mt "${MAX_TOTAL:-50}" \
    '{pattern: $p, context_lines: 3, max_total_matches: ($mt | tonumber)}
    + (if $pp != "" then {path: $pp} else {} end)
    + (if $cs != "" then {case_sensitive: ($cs == "true")} else {} end)
    + (if $ww != "" then {whole_word: ($ww == "true")} else {} end)
    + (if $fs != "" then {fixed_string: ($fs == "true")} else {} end)
    + (if $om != "" then {output_mode: $om} else {} end)
    + (if $hl != "" then {highlight: ($hl == "true")} else {} end)
    + (if $ex != "" then {exhaustive: ($ex == "true")} else {} end)
    + (if $la != "" then {A: ($la | tonumber)} else {} end)
    + (if $lb != "" then {B: ($lb | tonumber)} else {} end)
    + (if $mpf != "" then {max_matches_per_file: ($mpf | tonumber)} else {} end)'
}

# Auto-init auth on source
nia_auth
