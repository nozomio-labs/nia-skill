#!/usr/bin/env bash
# Nia FS — filesystem operations on indexed sources
# Usage: fs.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── info — get filesystem info for a source
cmd_info() {
  if [ -z "$1" ]; then echo "Usage: fs.sh info <source_id>"; return 1; fi
  local sid=$(resolve_source_id "$1")
  nia_get "$BASE_URL/fs/${sid}/info"
}

# ─── tree — get the file tree of a source
cmd_tree() {
  if [ -z "$1" ]; then echo "Usage: fs.sh tree <source_id> [path]"; return 1; fi
  local sid=$(resolve_source_id "$1")
  local url="$BASE_URL/fs/${sid}/tree"
  if [ -n "${2:-}" ]; then url="${url}?path=$(urlencode "$2")"; fi
  nia_get "$url"
}

# ─── ls — list directory contents
cmd_ls() {
  if [ -z "$1" ]; then echo "Usage: fs.sh ls <source_id> [path]"; return 1; fi
  local sid=$(resolve_source_id "$1")
  local path="${2:-/}"
  nia_get "$BASE_URL/fs/${sid}/ls?path=$(urlencode "$path")"
}

# ─── read — read a file from an indexed source
cmd_read() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh read <source_id> <path> [line_start] [line_end]"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  local url="$BASE_URL/fs/${sid}/read?path=$(urlencode "$2")"
  if [ -n "${3:-}" ]; then url="${url}&line_start=$3"; fi
  if [ -n "${4:-}" ]; then url="${url}&line_end=$4"; fi
  nia_get "$url"
}

# ─── find — find files matching a glob pattern
cmd_find() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh find <source_id> <glob_pattern>"
    echo "  pattern: e.g. '**/*.ts', 'src/*.py'"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  nia_get "$BASE_URL/fs/${sid}/find?pattern=$(urlencode "$2")"
}

# ─── grep — regex search in source files
cmd_grep() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh grep <source_id> <pattern> [path]"
    echo "  Env: CASE_SENSITIVE, WHOLE_WORD, FIXED_STRING, OUTPUT_MODE,"
    echo "       HIGHLIGHT, LINES_AFTER, LINES_BEFORE, MAX_PER_FILE, MAX_TOTAL,"
    echo "       CONTEXT_LINES, MULTILINE, INCLUDE_LINE_NUMBERS"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  DATA=$(build_grep_json "$2" "${3:-}")
  nia_post "$BASE_URL/fs/${sid}/grep" "$DATA"
}

# ─── write — write a file to an indexed source
cmd_write() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh write <source_id> <path> [local_file]"
    echo "  Reads content from local_file or stdin"
    echo "  Env: LANGUAGE, ENCODING (default: utf8)"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  local path="$2" body
  if [ -n "${3:-}" ] && [ -f "$3" ]; then
    body=$(cat "$3")
  else
    body=$(cat)
  fi
  DATA=$(jq -n \
    --arg path "$path" --arg body "$body" \
    --arg lang "${LANGUAGE:-}" --arg enc "${ENCODING:-utf8}" \
    '{path: $path, body: $body, encoding: $enc}
    + (if $lang != "" then {language: $lang} else {} end)')
  nia_put "$BASE_URL/fs/${sid}/files" "$DATA"
}

# ─── write-batch — write multiple files at once
cmd_write_batch() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh write-batch <source_id> <files_json>"
    echo '  files_json: [{"path":"a.txt","body":"content"}, ...]'
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  DATA=$(jq -n --argjson files "$2" '{files: $files}')
  nia_put "$BASE_URL/fs/${sid}/files/batch" "$DATA"
}

# ─── delete — delete a file from an indexed source
cmd_delete() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh delete <source_id> <path>"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  nia_curl DELETE "$BASE_URL/fs/${sid}/files?path=$(urlencode "$2")" | jq '.'
}

# ─── mkdir — create a directory in an indexed source
cmd_mkdir() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: fs.sh mkdir <source_id> <path>"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  DATA=$(jq -n --arg path "$2" '{path: $path}')
  nia_post "$BASE_URL/fs/${sid}/mkdir" "$DATA"
}

# ─── mv — move/rename a file in an indexed source
cmd_mv() {
  if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: fs.sh mv <source_id> <old_path> <new_path>"
    return 1
  fi
  local sid=$(resolve_source_id "$1")
  DATA=$(jq -n --arg old "$2" --arg new "$3" '{old_path: $old, new_path: $new}')
  nia_post "$BASE_URL/fs/${sid}/mv" "$DATA"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  info)        shift; cmd_info "$@" ;;
  tree)        shift; cmd_tree "$@" ;;
  ls)          shift; cmd_ls "$@" ;;
  read)        shift; cmd_read "$@" ;;
  find)        shift; cmd_find "$@" ;;
  grep)        shift; cmd_grep "$@" ;;
  write)       shift; cmd_write "$@" ;;
  write-batch) shift; cmd_write_batch "$@" ;;
  delete)      shift; cmd_delete "$@" ;;
  mkdir)       shift; cmd_mkdir "$@" ;;
  mv)          shift; cmd_mv "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Filesystem operations on indexed sources."
    echo ""
    echo "Commands:"
    echo "  info         Get source filesystem info"
    echo "  tree         Get file tree [path]"
    echo "  ls           List directory contents [path]"
    echo "  read         Read a file [line_start] [line_end]"
    echo "  find         Find files by glob pattern"
    echo "  grep         Regex search in files"
    echo "  write        Write a file (from file or stdin)"
    echo "  write-batch  Write multiple files at once"
    echo "  delete       Delete a file"
    echo "  mkdir        Create a directory"
    echo "  mv           Move/rename a file"
    exit 1
    ;;
esac
