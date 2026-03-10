#!/usr/bin/env bash
# Nia Local Folders — private file storage and search
# Usage: folders.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# helper: scan local dir into JSON files array
_scan_folder() {
  local folder_path="$1"
  local files_json="[]"
  while IFS= read -r -d '' file; do
    local rel="${file#$folder_path/}"
    if file "$file" | grep -q "text"; then
      local content
      content=$(cat "$file" 2>/dev/null || echo "")
      if [ -n "$content" ]; then
        files_json=$(echo "$files_json" | jq --arg p "$rel" --arg c "$content" '. + [{path: $p, content: $c}]')
      fi
    fi
  done < <(find "$folder_path" -type f -not -path '*/\.*' -not -name '*.pyc' -not -name '*.o' -not -name '*.so' -print0 2>/dev/null)
  echo "$files_json"
}

# ─── create — upload a local directory to Nia as a private, searchable folder
cmd_create() {
  if [ -z "$1" ]; then echo "Usage: folders.sh create /path/to/folder [display_name]"; return 1; fi
  if [ ! -d "$1" ]; then echo "Error: Directory not found: $1"; return 1; fi
  local folder_name="$(basename "$1")"
  local display_name="${2:-${DISPLAY_NAME:-}}"
  local files_json
  files_json=$(_scan_folder "$1")
  local count
  count=$(echo "$files_json" | jq 'length')
  echo "Found $count text files to index"
  if [ "$count" -eq 0 ]; then echo "Error: No indexable files"; return 1; fi
  DATA=$(jq -n --arg folder_name "$folder_name" --arg path "$1" --argjson files "$files_json" --arg display_name "$display_name" \
    '{type: "local_folder", folder_name: $folder_name, folder_path: $path, files: $files}
    + (if $display_name != "" then {display_name: $display_name} else {} end)')
  nia_post "$BASE_URL/sources" "$DATA"
}

# ─── create-db — upload a database file as a private local source
cmd_create_db() {
  if [ -z "$1" ]; then
    echo "Usage: folders.sh create-db <database_file> [display_name]"
    return 1
  fi
  if [ ! -f "$1" ]; then echo "Error: File not found: $1"; return 1; fi
  local filename display_name encoded
  filename="$(basename "$1")"
  display_name="${2:-${DISPLAY_NAME:-$filename}}"
  encoded=$(base64 < "$1" | tr -d '\n')
  DATA=$(jq -n --arg name "$display_name" --arg filename "$filename" --arg content "$encoded" \
    '{type: "local_folder", folder_name: $name, display_name: $name, database: {filename: $filename, content: $content}}')
  nia_post "$BASE_URL/sources" "$DATA"
}

# ─── list — list all local folders, optionally filtered by status/query/category
cmd_list() {
  local limit="${1:-50}" offset="${2:-0}"
  local url="$BASE_URL/sources?type=local_folder&limit=${limit}&offset=${offset}"
  if [ -n "${STATUS:-}" ]; then url="${url}&status=$(echo "$STATUS" | jq -Rr @uri)"; fi
  if [ -n "${QUERY:-}" ]; then url="${url}&query=$(echo "$QUERY" | jq -Rr @uri)"; fi
  if [ -n "${CATEGORY_ID:-}" ]; then url="${url}&category_id=$(echo "$CATEGORY_ID" | jq -Rr @uri)"; fi
  nia_get "$url"
}

# ─── get — fetch details for a single local folder by ID
cmd_get() {
  if [ -z "$1" ]; then echo "Usage: folders.sh get <folder_id>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  nia_get "$BASE_URL/sources/${sid}?type=local_folder"
}

# ─── delete — remove a local folder and its indexed content
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: folders.sh delete <folder_id>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  nia_delete "$BASE_URL/sources/${sid}?type=local_folder"
}

# ─── rename — change the display name of a local folder
cmd_rename() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: folders.sh rename <folder_id> <new_name>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  DATA=$(jq -n --arg name "$2" '{display_name: $name}')
  nia_patch "$BASE_URL/sources/${sid}?type=local_folder" "$DATA"
}

# ─── tree — print the file tree of a local folder
cmd_tree() {
  if [ -z "$1" ]; then echo "Usage: folders.sh tree <folder_id>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  local url="$BASE_URL/sources/${sid}/tree?type=local_folder&max_depth=${MAX_DEPTH:-10}"
  nia_get_raw "$url" | jq '.tree_string // .formatted_tree // .'
}

# ─── ls — list files and subdirectories at a path in a local folder
cmd_ls() {
  if [ -z "$1" ]; then echo "Usage: folders.sh ls <folder_id>"; return 1; fi
  if [ -n "${2:-}" ]; then
    echo "Error: path-scoped ls is not exposed by the unified /sources tree endpoint. Use tree, read, or grep."
    return 1
  fi
  MAX_DEPTH="${MAX_DEPTH:-2}" cmd_tree "$1"
}

# ─── read — read file content from a local folder by path and optional line range
cmd_read() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: folders.sh read <folder_id> <file_path>"
    echo "  Env: LINE_START, LINE_END, MAX_LENGTH"
    return 1
  fi
  local sid fpath url
  sid=$(resolve_source_id "$1" local_folder)
  fpath=$(urlencode "$2")
  url="$BASE_URL/sources/${sid}/content?type=local_folder&path=${fpath}"
  if [ -n "${LINE_START:-}" ]; then url="${url}&line_start=${LINE_START}"; fi
  if [ -n "${LINE_END:-}" ]; then url="${url}&line_end=${LINE_END}"; fi
  if [ -n "${MAX_LENGTH:-}" ]; then url="${url}&max_length=${MAX_LENGTH}"; fi
  nia_get_raw "$url" | jq -r '.content // .'
}

# ─── grep — regex search across all files in a local folder
cmd_grep() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: folders.sh grep <folder_id> <pattern> [path_prefix]"
    echo "  Env: CASE_SENSITIVE, WHOLE_WORD, FIXED_STRING, OUTPUT_MODE,"
    echo "       HIGHLIGHT, EXHAUSTIVE, LINES_AFTER, LINES_BEFORE, MAX_PER_FILE, MAX_TOTAL"
    return 1
  fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  DATA=$(build_grep_json "$2" "${3:-}")
  nia_post "$BASE_URL/sources/${sid}/grep?type=local_folder" "$DATA"
}

# ─── classify — auto-classify folder files into your categories using AI
cmd_classify() {
  if [ -z "$1" ]; then
    echo "Usage: folders.sh classify <folder_id> [categories_csv]"
    echo "  categories_csv  Comma-separated category names (uses existing categories if omitted)"
    return 1
  fi
  local cats="${2:-}"
  if [ -n "$cats" ]; then
    DATA=$(jq -n --arg c "$cats" '{categories: ($c | split(","))}')
  else
    # Fetch existing categories and pass them
    local existing
    existing=$(nia_get_raw "$BASE_URL/categories" | jq -r '[.items[]?.name // empty] | join(",")')
    if [ -z "$existing" ]; then
      echo "Error: No categories found. Create some first with: categories.sh create <name>"
      return 1
    fi
    DATA=$(jq -n --arg c "$existing" '{categories: ($c | split(","))}')
  fi
  if [ -n "${INCLUDE_UNCATEGORIZED:-}" ]; then
    DATA=$(echo "$DATA" | jq --arg iu "$INCLUDE_UNCATEGORIZED" '. + {include_uncategorized: ($iu == "true")}')
  fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  nia_patch "$BASE_URL/sources/${sid}/classification?type=local_folder" "$DATA"
}

# ─── classification — get the current classification result for a folder
cmd_classification() {
  if [ -z "$1" ]; then echo "Usage: folders.sh classification <folder_id>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  nia_get "$BASE_URL/sources/${sid}/classification?type=local_folder"
}

# ─── sync — re-upload local files to an existing folder to pick up changes
cmd_sync() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: folders.sh sync <folder_id> /path/to/folder"; return 1; fi
  if [ ! -d "$2" ]; then echo "Error: Directory not found: $2"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  local files_json
  files_json=$(_scan_folder "$2")
  local count
  count=$(echo "$files_json" | jq 'length')
  echo "Syncing $count text files"
  DATA=$(jq -n --arg path "$2" --argjson files "$files_json" '{folder_path: $path, files: $files}')
  nia_post "$BASE_URL/sources/${sid}/sync?type=local_folder" "$DATA"
}

# ─── assign-category — assign or remove a category for a local folder
cmd_assign_category() {
  if [ -z "$1" ] || [ -z "$2" ]; then echo "Usage: folders.sh assign-category <folder_id> <category_id|null>"; return 1; fi
  local sid
  sid=$(resolve_source_id "$1" local_folder)
  if [ "$2" = "null" ]; then
    DATA='{"category_id": null}'
  else
    DATA=$(jq -n --arg c "$2" '{category_id: $c}')
  fi
  nia_patch "$BASE_URL/sources/${sid}?type=local_folder" "$DATA"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  create)          shift; cmd_create "$@" ;;
  create-db)       shift; cmd_create_db "$@" ;;
  list)            shift; cmd_list "$@" ;;
  get)             shift; cmd_get "$@" ;;
  delete)          shift; cmd_delete "$@" ;;
  rename)          shift; cmd_rename "$@" ;;
  tree)            shift; cmd_tree "$@" ;;
  ls)              shift; cmd_ls "$@" ;;
  read)            shift; cmd_read "$@" ;;
  grep)            shift; cmd_grep "$@" ;;
  classify)        shift; cmd_classify "$@" ;;
  classification)  shift; cmd_classification "$@" ;;
  sync)            shift; cmd_sync "$@" ;;
  assign-category) shift; cmd_assign_category "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  create          Create folder from local directory"
    echo "  create-db       Create local source from database file"
    echo "  list            List local folders"
    echo "  get             Get folder details"
    echo "  delete          Delete a folder"
    echo "  rename          Rename a folder"
    echo "  tree            Get folder file tree"
    echo "  ls              List directory in folder"
    echo "  read            Read file from folder"
    echo "  grep            Search folder content with regex"
    echo "  classify        Auto-classify folder into categories"
    echo "  classification  Get folder classification"
    echo "  sync            Re-sync folder from local path"
    echo "  assign-category Assign/remove category"
    exit 1
    ;;
esac
