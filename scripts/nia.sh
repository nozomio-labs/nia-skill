#!/usr/bin/env bash
# Nia CLI — unified entry point
# Usage: nia.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── sources — quick inventory of all indexed sources
cmd_sources() {
  nia_auth
  local raw
  raw=$(nia_get "$BASE_URL/sources-summary")

  local repos docs papers datasets folders slack drive
  repos=$(echo "$raw" | jq -r '.repositories.count // 0')
  docs=$(echo "$raw" | jq -r '.documentation.count // 0')
  papers=$(echo "$raw" | jq -r '.research_papers.count // 0')
  datasets=$(echo "$raw" | jq -r '.huggingface_datasets.count // 0')
  folders=$(echo "$raw" | jq -r '.local_folders.count // 0')
  slack=$(echo "$raw" | jq -r '.slack.count // 0')
  drive=$(echo "$raw" | jq -r '.google_drive.count // 0')

  echo "=== Nia Sources Summary ==="
  echo ""

  _print_type "Repositories" "$repos" "$(echo "$raw" | jq -r '(.repositories.names // [])[:5] | join(", ")')"
  _print_type "Documentation" "$docs" "$(echo "$raw" | jq -r '(.documentation.names // [])[:5] | join(", ")')"
  _print_type "Research Papers" "$papers" "$(echo "$raw" | jq -r '(.research_papers.names // [])[:5] | join(", ")')"
  _print_type "HuggingFace Datasets" "$datasets" "$(echo "$raw" | jq -r '(.huggingface_datasets.names // [])[:5] | join(", ")')"
  _print_type "Local Folders" "$folders" "$(echo "$raw" | jq -r '(.local_folders.names // [])[:5] | join(", ")')"
  _print_type "Slack" "$slack" "$(echo "$raw" | jq -r '(.slack.names // [])[:5] | join(", ")')"
  _print_type "Google Drive" "$drive" "$(echo "$raw" | jq -r '(.google_drive.names // [])[:5] | join(", ")')"

  echo ""
  echo "For full details, use: repos.sh list, sources.sh list, slack.sh list, google-drive.sh list, folders.sh list"
}

_print_type() {
  local label="$1" count="$2" names="$3"
  if [ "$count" -eq 0 ]; then
    printf "  %-22s %s\n" "$label:" "0"
  else
    printf "  %-22s %s\n" "$label:" "$count"
    if [ -n "$names" ]; then
      printf "    %s\n" "$names"
    fi
  fi
}

# ─── dispatch
case "${1:-}" in
  sources)  shift; cmd_sources "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  sources    Quick inventory of all indexed sources"
    exit 1
    ;;
esac
