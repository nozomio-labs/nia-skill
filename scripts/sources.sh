#!/usr/bin/env bash
# Nia Sources — unified source management
# Usage: sources.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── index — crawl and index a documentation site, PDF, or any URL
cmd_index() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh index 'https://docs.example.com' [limit]"
    echo ""
    echo "Environment variables:"
    echo "  DISPLAY_NAME          Custom display name"
    echo "  FOCUS                 Focus instructions (e.g. 'Only API reference')"
    echo "  EXTRACT_BRANDING      Extract brand colors, logos, fonts (true/false)"
    echo "  EXTRACT_IMAGES        Extract all image URLs (true/false)"
    echo "  IS_PDF                Direct PDF URL (true/false)"
    echo "  IS_SPREADSHEET        Spreadsheet file - CSV, TSV, XLSX, XLS (true/false)"
    echo "  URL_PATTERNS          Comma-separated include patterns"
    echo "  EXCLUDE_PATTERNS      Comma-separated exclude patterns"
    echo "  MAX_DEPTH             Maximum crawl depth (default: 20)"
    echo "  WAIT_FOR              Wait for page load in ms (default: 2000)"
    echo "  CHECK_LLMS_TXT        Check for llms.txt (true/false, default: true)"
    echo "  LLMS_TXT_STRATEGY     prefer|only|ignore (default: prefer)"
    echo "  INCLUDE_SCREENSHOT    Include full page screenshot (true/false)"
    echo "  ONLY_MAIN_CONTENT     Extract only main content (true/false, default: true)"
    echo "  ADD_GLOBAL            Add as global source (true/false, default: true)"
    echo "  MAX_AGE               Cache max age in seconds"
    return 1
  fi
  local url="$1" limit="${2:-1000}"
  DATA=$(jq -n \
    --arg u "$url" \
    --argjson l "$limit" \
    --arg display_name "${DISPLAY_NAME:-}" \
    --arg focus "${FOCUS:-}" \
    --arg extract_branding "${EXTRACT_BRANDING:-}" \
    --arg extract_images "${EXTRACT_IMAGES:-}" \
    --arg is_pdf "${IS_PDF:-}" \
    --arg is_spreadsheet "${IS_SPREADSHEET:-}" \
    --arg url_patterns "${URL_PATTERNS:-}" \
    --arg exclude_patterns "${EXCLUDE_PATTERNS:-}" \
    --arg max_depth "${MAX_DEPTH:-}" \
    --arg wait_for "${WAIT_FOR:-}" \
    --arg check_llms_txt "${CHECK_LLMS_TXT:-}" \
    --arg llms_txt_strategy "${LLMS_TXT_STRATEGY:-}" \
    --arg include_screenshot "${INCLUDE_SCREENSHOT:-}" \
    --arg only_main_content "${ONLY_MAIN_CONTENT:-true}" \
    --arg add_global "${ADD_GLOBAL:-}" \
    --arg max_age "${MAX_AGE:-}" \
    '{type: "documentation", url: $u, limit: $l, only_main_content: ($only_main_content == "true")}
    + (if $display_name != "" then {display_name: $display_name} else {} end)
    + (if $focus != "" then {focus_instructions: $focus} else {} end)
    + (if $extract_branding != "" then {extract_branding: ($extract_branding == "true")} else {} end)
    + (if $extract_images != "" then {extract_images: ($extract_images == "true")} else {} end)
    + (if $is_pdf != "" then {is_pdf: ($is_pdf == "true")} else {} end)
    + (if $is_spreadsheet != "" then {is_spreadsheet: ($is_spreadsheet == "true")} else {} end)
    + (if $url_patterns != "" then {url_patterns: ($url_patterns | split(","))} else {} end)
    + (if $exclude_patterns != "" then {exclude_patterns: ($exclude_patterns | split(","))} else {} end)
    + (if $max_depth != "" then {max_depth: ($max_depth | tonumber)} else {} end)
    + (if $wait_for != "" then {wait_for: ($wait_for | tonumber)} else {} end)
    + (if $check_llms_txt != "" then {check_llms_txt: ($check_llms_txt == "true")} else {} end)
    + (if $llms_txt_strategy != "" then {llms_txt_strategy: $llms_txt_strategy} else {} end)
    + (if $include_screenshot != "" then {include_screenshot: ($include_screenshot == "true")} else {} end)
    + (if $add_global != "" then {add_as_global_source: ($add_global == "true")} else {} end)
    + (if $max_age != "" then {max_age: ($max_age | tonumber)} else {} end)')
  nia_post "$BASE_URL/sources" "$DATA"
}

# ─── list — list all indexed sources, optionally filtered by type
cmd_list() {
  local type="${1:-}" limit="${2:-}" offset="${3:-}"
  local url="$BASE_URL/sources"
  local sep="?"
  if [ -n "$type" ]; then url="${url}${sep}type=${type}"; sep="&"; fi
  if [ -n "$limit" ]; then url="${url}${sep}limit=${limit}"; sep="&"; fi
  if [ -n "$offset" ]; then url="${url}${sep}offset=${offset}"; sep="&"; fi
  if [ -n "${STATUS:-}" ]; then url="${url}${sep}status=$(echo "$STATUS" | jq -Rr @uri)"; sep="&"; fi
  if [ -n "${QUERY:-}" ]; then url="${url}${sep}query=$(echo "$QUERY" | jq -Rr @uri)"; sep="&"; fi
  if [ -n "${CATEGORY_ID:-}" ]; then url="${url}${sep}category_id=$(echo "$CATEGORY_ID" | jq -Rr @uri)"; fi
  nia_get "$url"
}

# ─── get — fetch full details for a single source by ID
cmd_get() {
  if [ -z "$1" ]; then echo "Usage: sources.sh get <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-}") type="${2:-}"
  local url="$BASE_URL/sources/${sid}"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_get "$url"
}

# ─── resolve — look up a source by name, URL, or identifier
cmd_resolve() {
  if [ -z "$1" ]; then echo "Usage: sources.sh resolve <identifier> [type]"; return 1; fi
  local id=$(urlencode "$1") type="${2:-}"
  local url="$BASE_URL/sources/resolve?identifier=${id}"
  if [ -n "$type" ]; then url="${url}&type=${type}"; fi
  nia_get "$url"
}

# ─── update — change a source's display name or category assignment
cmd_update() {
  if [ -z "$1" ]; then echo "Usage: sources.sh update <source_id> [display_name] [category_id]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${TYPE:-}") dname="${2:-}" cat_id="${3:-}"
  DATA=$(jq -n --arg dn "$dname" --arg cat "$cat_id" \
    '{} + (if $dn != "" then {display_name: $dn} else {} end)
       + (if $cat == "null" then {category_id: null} elif $cat != "" then {category_id: $cat} else {} end)')
  local url="$BASE_URL/sources/${sid}"
  if [ -n "${TYPE:-}" ]; then url="${url}?type=${TYPE}"; fi
  nia_patch "$url" "$DATA"
}

# ─── delete — remove a source and all its indexed content
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: sources.sh delete <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-}") type="${2:-}"
  local url="$BASE_URL/sources/${sid}"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_delete "$url"
}

# ─── sync — re-index a source to pick up upstream changes
cmd_sync() {
  if [ -z "$1" ]; then echo "Usage: sources.sh sync <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-}") type="${2:-}"
  local url="$BASE_URL/sources/${sid}/sync"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_post "$url" "${SYNC_JSON:-{}}"
}

# ─── rename — change the display name of any source
cmd_rename() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: sources.sh rename <source_id> <new_name>"; return 1; fi
  local sid=$(resolve_source_id "$1" "${TYPE:-}")
  DATA=$(jq -n --arg name "$2" '{display_name: $name}')
  nia_patch "$BASE_URL/sources/${sid}" "$DATA"
}

# ─── subscribe — add a publicly indexed global source to your account
cmd_subscribe() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh subscribe <url> [source_type] [ref]"
    echo "  source_type: repository|documentation|research_paper|huggingface_dataset"
    return 1
  fi
  DATA=$(jq -n --arg u "$1" --arg st "${2:-}" --arg ref "${3:-}" \
    '{url: $u} + (if $st != "" then {source_type: $st} else {} end) + (if $ref != "" then {ref: $ref} else {} end)')
  nia_post "$BASE_URL/sources/subscribe" "$DATA"
}

# ─── read — read file content from an indexed source by path and optional line range
cmd_read() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh read <source_id> [path]"
    echo "  Env: TYPE=<source_type>, BRANCH, URL, PAGE, TREE_NODE_ID,"
    echo "       LINE_START, LINE_END, MAX_LENGTH"
    return 1
  fi
  local sid path url sep
  sid=$(resolve_source_id "$1" "${TYPE:-}")
  path="${2:-}"
  url="$BASE_URL/sources/${sid}/content"
  sep="?"
  if [ -n "${TYPE:-}" ]; then url="${url}${sep}type=${TYPE}"; sep="&"; fi
  if [ -n "$path" ]; then url="${url}${sep}path=$(urlencode "$path")"; sep="&"; fi
  if [ -n "${URL:-}" ]; then url="${url}${sep}url=$(urlencode "$URL")"; sep="&"; fi
  if [ -n "${BRANCH:-}" ]; then url="${url}${sep}branch=$(urlencode "$BRANCH")"; sep="&"; fi
  if [ -n "${PAGE:-}" ]; then url="${url}${sep}page=${PAGE}"; sep="&"; fi
  if [ -n "${TREE_NODE_ID:-}" ]; then url="${url}${sep}tree_node_id=$(urlencode "$TREE_NODE_ID")"; sep="&"; fi
  if [ -n "${LINE_START:-}" ]; then url="${url}${sep}line_start=${LINE_START}"; sep="&"; fi
  if [ -n "${LINE_END:-}" ]; then url="${url}${sep}line_end=${LINE_END}"; sep="&"; fi
  if [ -n "${MAX_LENGTH:-}" ]; then url="${url}${sep}max_length=${MAX_LENGTH}"; fi
  nia_get_raw "$url" | jq -r '.content // .'
}

# ─── grep — regex search across all files in a source
cmd_grep() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: sources.sh grep <source_id> <pattern> [path]"
    echo "  Env: CASE_SENSITIVE, WHOLE_WORD, FIXED_STRING, OUTPUT_MODE,"
    echo "       HIGHLIGHT, EXHAUSTIVE, LINES_AFTER, LINES_BEFORE, MAX_PER_FILE, MAX_TOTAL, TYPE"
    return 1
  fi
  local sid=$(resolve_source_id "$1" "${TYPE:-}")
  DATA=$(build_grep_json "$2" "${3:-}")
  local url="$BASE_URL/sources/${sid}/grep"
  if [ -n "${TYPE:-}" ]; then url="${url}?type=${TYPE}"; fi
  nia_post "$url" "$DATA"
}

# ─── tree — print the full file tree of a source
cmd_tree() {
  if [ -z "$1" ]; then echo "Usage: sources.sh tree <source_id>"; return 1; fi
  local sid=$(resolve_source_id "$1" "${TYPE:-}")
  local url="$BASE_URL/sources/${sid}/tree"
  local sep="?"
  if [ -n "${TYPE:-}" ]; then url="${url}${sep}type=${TYPE}"; sep="&"; fi
  if [ -n "${BRANCH:-}" ]; then url="${url}${sep}branch=$(urlencode "$BRANCH")"; sep="&"; fi
  if [ -n "${MAX_DEPTH:-}" ]; then url="${url}${sep}max_depth=${MAX_DEPTH}"; fi
  nia_get_raw "$url" | jq '.tree_string // .formatted_tree // .'
}

# ─── ls — list files/dirs in a specific path within a source
cmd_ls() {
  if [ -z "$1" ]; then echo "Usage: sources.sh ls <source_id>"; return 1; fi
  if [ -n "${2:-}" ]; then
    echo "Error: the current /sources tree endpoint is not path-scoped. Use tree, read, or grep instead."
    return 1
  fi
  MAX_DEPTH="${MAX_DEPTH:-2}" cmd_tree "$1"
}

# ─── classification — get or update the auto-classification for a source
cmd_classification() {
  if [ -z "$1" ]; then echo "Usage: sources.sh classification <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-${TYPE:-}}") type="${2:-${TYPE:-}}"
  local url="$BASE_URL/sources/${sid}/classification"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  if [ "${ACTION:-}" = "update" ]; then
    if [ -z "${CATEGORIES:-}" ]; then
      echo "Error: set CATEGORIES=cat1,cat2 to update classification"
      return 1
    fi
    DATA=$(jq -n --arg c "$CATEGORIES" --arg iu "${INCLUDE_UNCATEGORIZED:-}" \
      '{categories: ($c | split(","))}
      + (if $iu != "" then {include_uncategorized: ($iu == "true")} else {} end)')
    nia_patch "$url" "$DATA"
  else
    nia_get "$url"
  fi
}

# ─── curation — fetch trust signals, overlay guidance, and annotations for a source
cmd_curation() {
  if [ -z "$1" ]; then echo "Usage: sources.sh curation <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-${TYPE:-}}") type="${2:-${TYPE:-}}"
  local url="$BASE_URL/sources/${sid}/curation"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_get "$url"
}

# ─── update-curation — update source trust level or curated overlay
cmd_update_curation() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh update-curation <source_id> [type]"
    echo "  Env: TRUST_LEVEL, OVERLAY_KIND, OVERLAY_SUMMARY, OVERLAY_GUIDANCE,"
    echo "       RECOMMENDED_QUERIES, CLEAR_OVERLAY"
    return 1
  fi
  if [ -z "${TRUST_LEVEL:-}${OVERLAY_KIND:-}${OVERLAY_SUMMARY:-}${OVERLAY_GUIDANCE:-}${RECOMMENDED_QUERIES:-}${CLEAR_OVERLAY:-}" ]; then
    echo "Error: set at least one of TRUST_LEVEL, OVERLAY_KIND, OVERLAY_SUMMARY, OVERLAY_GUIDANCE, RECOMMENDED_QUERIES, CLEAR_OVERLAY"
    return 1
  fi
  local sid=$(resolve_source_id "$1" "${2:-${TYPE:-}}") type="${2:-${TYPE:-}}"
  DATA=$(jq -n \
    --arg trust "${TRUST_LEVEL:-}" --arg kind "${OVERLAY_KIND:-}" \
    --arg summary "${OVERLAY_SUMMARY:-}" --arg guidance "${OVERLAY_GUIDANCE:-}" \
    --arg queries "${RECOMMENDED_QUERIES:-}" --arg clear "${CLEAR_OVERLAY:-}" \
    '{} + (if $trust != "" then {trust_level: $trust} else {} end)
       + (if $kind != "" then {overlay_kind: $kind} else {} end)
       + (if $summary != "" then {overlay_summary: $summary} else {} end)
       + (if $guidance != "" then {overlay_guidance: $guidance} else {} end)
       + (if $queries != "" then {recommended_queries: ($queries | split(","))} else {} end)
       + (if $clear != "" then {clear_overlay: ($clear == "true")} else {} end)')
  local url="$BASE_URL/sources/${sid}/curation"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_put "$url" "$DATA"
}

# ─── annotations — list saved annotations for a source
cmd_annotations() {
  if [ -z "$1" ]; then echo "Usage: sources.sh annotations <source_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${2:-${TYPE:-}}") type="${2:-${TYPE:-}}"
  local url="$BASE_URL/sources/${sid}/annotations"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_get "$url"
}

# ─── add-annotation — attach a note/tip/warning/gotcha to a source
cmd_add_annotation() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: sources.sh add-annotation <source_id> <content> [kind] [type]"
    return 1
  fi
  local sid=$(resolve_source_id "$1" "${4:-${TYPE:-}}") type="${4:-${TYPE:-}}"
  DATA=$(jq -n --arg content "$2" --arg kind "${3:-note}" \
    '{content: $content}
    + (if $kind != "" then {kind: $kind} else {} end)')
  local url="$BASE_URL/sources/${sid}/annotations"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_post "$url" "$DATA"
}

# ─── update-annotation — update an existing source annotation
cmd_update_annotation() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: sources.sh update-annotation <source_id> <annotation_id> [content] [kind] [type]"
    echo "  Pass '' for content to update only kind, or use ANNOTATION_CONTENT / ANNOTATION_KIND env vars."
    return 1
  fi
  local content="${3:-${ANNOTATION_CONTENT:-}}"
  local kind="${4:-${ANNOTATION_KIND:-}}"
  if [ -z "$content" ] && [ -z "$kind" ]; then
    echo "Error: provide content and/or kind"
    return 1
  fi
  local sid=$(resolve_source_id "$1" "${5:-${TYPE:-}}") type="${5:-${TYPE:-}}"
  DATA=$(jq -n --arg content "$content" --arg kind "$kind" \
    '{} + (if $content != "" then {content: $content} else {} end)
       + (if $kind != "" then {kind: $kind} else {} end)')
  local url="$BASE_URL/sources/${sid}/annotations/$2"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_patch "$url" "$DATA"
}

# ─── delete-annotation — remove an annotation from a source
cmd_delete_annotation() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: sources.sh delete-annotation <source_id> <annotation_id> [type]"; return 1; fi
  local sid=$(resolve_source_id "$1" "${3:-${TYPE:-}}") type="${3:-${TYPE:-}}"
  local url="$BASE_URL/sources/${sid}/annotations/$2"
  if [ -n "$type" ]; then url="${url}?type=${type}"; fi
  nia_delete "$url"
}

# ─── assign-category — assign (or remove with 'null') a category for a source
cmd_assign_category() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: sources.sh assign-category <source_id> <category_id|null>"; return 1; fi
  local sid=$(resolve_source_id "$1" "${TYPE:-}") cat_id="$2"
  if [ "$cat_id" = "null" ]; then
    DATA='{"category_id": null}'
  else
    DATA=$(jq -n --arg c "$cat_id" '{category_id: $c}')
  fi
  local url="$BASE_URL/sources/${sid}"
  if [ -n "${TYPE:-}" ]; then url="${url}?type=${TYPE}"; fi
  nia_patch "$url" "$DATA"
}

# ─── upload-url — get a signed URL for file upload (PDF, spreadsheets)
cmd_upload_url() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh upload-url <filename>"
    echo "  Returns signed URL for HTTP PUT upload and gcs_path for create-source"
    echo "  Supports: PDF, CSV, TSV, XLSX, XLS"
    return 1
  fi
  local filename="$1"
  local content_type="application/pdf"
  case "${filename##*.}" in
    csv)  content_type="text/csv" ;;
    tsv)  content_type="text/tab-separated-values" ;;
    xlsx) content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ;;
    xls)  content_type="application/vnd.ms-excel" ;;
  esac
  DATA=$(jq -n --arg fn "$filename" --arg ct "$content_type" '{filename: $fn, content_type: $ct}')
  nia_post "$BASE_URL/sources/upload-url" "$DATA"
}

# ─── bulk-delete — delete multiple resources in a single request
cmd_bulk_delete() {
  if [ -z "$1" ]; then
    echo "Usage: sources.sh bulk-delete <id:type> [id:type ...]"
    echo "  type: repository|documentation|research_paper|context|local_folder"
    echo "  Example: sources.sh bulk-delete abc123:repository def456:documentation"
    return 1
  fi
  local items="[]"
  for item in "$@"; do
    local id="${item%%:*}" type="${item#*:}"
    case "$type" in
      repository|documentation|research_paper|context|local_folder) ;;
      *)
        echo "Unsupported bulk-delete type: $type"
        return 1
        ;;
    esac
    items=$(echo "$items" | jq --arg id "$id" --arg t "$type" '. + [{id: $id, type: $t}]')
  done
  DATA=$(jq -n --argjson items "$items" '{items: $items}')
  nia_post "$BASE_URL/bulk-delete" "$DATA"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  index)            shift; cmd_index "$@" ;;
  list)             shift; cmd_list "$@" ;;
  get)              shift; cmd_get "$@" ;;
  resolve)          shift; cmd_resolve "$@" ;;
  update)           shift; cmd_update "$@" ;;
  delete)           shift; cmd_delete "$@" ;;
  sync)             shift; cmd_sync "$@" ;;
  rename)           shift; cmd_rename "$@" ;;
  subscribe)        shift; cmd_subscribe "$@" ;;
  read)             shift; cmd_read "$@" ;;
  grep)             shift; cmd_grep "$@" ;;
  tree)             shift; cmd_tree "$@" ;;
  ls)               shift; cmd_ls "$@" ;;
  classification)   shift; cmd_classification "$@" ;;
  curation)         shift; cmd_curation "$@" ;;
  update-curation)  shift; cmd_update_curation "$@" ;;
  annotations)      shift; cmd_annotations "$@" ;;
  add-annotation)   shift; cmd_add_annotation "$@" ;;
  update-annotation) shift; cmd_update_annotation "$@" ;;
  delete-annotation) shift; cmd_delete_annotation "$@" ;;
  assign-category)  shift; cmd_assign_category "$@" ;;
  upload-url)       shift; cmd_upload_url "$@" ;;
  bulk-delete)      shift; cmd_bulk_delete "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  index            Index a documentation site"
    echo "  list [type]      List sources (repository|documentation|research_paper|huggingface_dataset|local_folder|slack|google_drive)"
    echo "  get              Get source details"
    echo "  resolve          Resolve source by name/URL"
    echo "  update           Update source display name / category"
    echo "  delete           Delete a source"
    echo "  sync             Re-sync a source"
    echo "  rename           Rename a data source"
    echo "  subscribe        Subscribe to a globally indexed source"
    echo "  read             Read content from a source"
    echo "  grep             Search source content with regex"
    echo "  tree             Get source file tree"
    echo "  ls               List directory in source"
    echo "  classification   Get/update source classification (PATCH uses ACTION=update and CATEGORIES=csv)"
    echo "  curation         Get source trust signals, overlay, and annotations"
    echo "  update-curation  Update trust level / curated overlay"
    echo "  annotations      List source annotations"
    echo "  add-annotation   Create source annotation"
    echo "  update-annotation Update source annotation"
    echo "  delete-annotation Delete source annotation"
    echo "  assign-category  Assign category to source"
    echo "  upload-url       Get signed URL for file upload (PDF, CSV, TSV, XLSX, XLS)"
    echo "  bulk-delete      Delete multiple resources at once"
    exit 1
    ;;
esac
