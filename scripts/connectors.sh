#!/usr/bin/env bash
# Nia Connectors — generic connector management
# Usage: connectors.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ─── list — list all available connector types
cmd_list() {
  nia_get "$BASE_URL/connectors"
}

# ─── installations — list all connector installations
cmd_installations() {
  nia_get "$BASE_URL/connectors/installations"
}

# ─── install — install a connector (store API key or start OAuth)
cmd_install() {
  if [ -z "$1" ]; then
    echo "Usage: connectors.sh install <connector_type>"
    return 1
  fi
  nia_post "$BASE_URL/connectors/$1/install" "{}"
}

# ─── delete — disconnect a connector installation
cmd_delete() {
  if [ -z "$1" ]; then echo "Usage: connectors.sh delete <installation_id>"; return 1; fi
  nia_delete "$BASE_URL/connectors/installations/$1"
}

# ─── index — trigger indexing for a connector installation
cmd_index() {
  if [ -z "$1" ]; then echo "Usage: connectors.sh index <installation_id>"; return 1; fi
  nia_post "$BASE_URL/connectors/installations/$1/index" "{}"
}

# ─── schedule — update sync schedule for a connector installation
cmd_schedule() {
  if [ -z "$1" ]; then echo "Usage: connectors.sh schedule <installation_id>"; return 1; fi
  nia_patch "$BASE_URL/connectors/installations/$1/schedule" "{}"
}

# ─── status — get sync status and health for a connector installation
cmd_status() {
  if [ -z "$1" ]; then echo "Usage: connectors.sh status <installation_id>"; return 1; fi
  nia_get "$BASE_URL/connectors/installations/$1/status"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  list)          shift; cmd_list "$@" ;;
  installations) shift; cmd_installations "$@" ;;
  install)       shift; cmd_install "$@" ;;
  delete)        shift; cmd_delete "$@" ;;
  index)         shift; cmd_index "$@" ;;
  schedule)      shift; cmd_schedule "$@" ;;
  status)        shift; cmd_status "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Generic connector management."
    echo ""
    echo "Commands:"
    echo "  list           List available connector types"
    echo "  installations  List connector installations"
    echo "  install        Install a connector by type"
    echo "  delete         Disconnect a connector installation"
    echo "  index          Trigger indexing for installation"
    echo "  schedule       Update sync schedule"
    echo "  status         Get installation sync status"
    exit 1
    ;;
esac
