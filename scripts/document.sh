#!/usr/bin/env bash
# Nia Document Agent — query indexed documents with AI
# Usage: document.sh <source_id> <query>
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: document.sh <source_id> <query>"
  echo ""
  echo "Query an indexed PDF or document with an AI agent that uses tools"
  echo "(search, read sections, read pages) to research and answer with citations."
  echo ""
  echo "Environment variables:"
  echo "  MODEL             Model to use (claude-opus-4-6-1m, claude-opus-4-6, claude-sonnet-4-5-20250929)"
  echo "  THINKING          Enable extended thinking (true/false, default: true)"
  echo "  THINKING_BUDGET   Token budget for thinking (1000-50000, default: 10000)"
  echo "  STREAM            Stream response as SSE (true/false, default: false)"
  echo "  JSON_SCHEMA       JSON schema string for structured output"
  echo "  JSON_SCHEMA_FILE  Path to JSON schema file for structured output"
  exit 1
fi

SID=$(resolve_source_id "$1")
QUERY="$2"

# Handle JSON schema from file or string
SCHEMA_JSON="null"
if [ -n "${JSON_SCHEMA_FILE:-}" ] && [ -f "$JSON_SCHEMA_FILE" ]; then
  SCHEMA_JSON=$(cat "$JSON_SCHEMA_FILE")
elif [ -n "${JSON_SCHEMA:-}" ]; then
  SCHEMA_JSON="$JSON_SCHEMA"
fi

DATA=$(jq -n \
  --arg sid "$SID" --arg q "$QUERY" \
  --argjson schema "$SCHEMA_JSON" \
  --arg model "${MODEL:-}" --arg thinking "${THINKING:-}" \
  --arg budget "${THINKING_BUDGET:-}" --arg stream "${STREAM:-}" \
  '{source_id: $sid, query: $q}
  + (if $schema != null then {json_schema: $schema} else {} end)
  + (if $model != "" then {model: $model} else {} end)
  + (if $thinking != "" then {thinking_enabled: ($thinking == "true")} else {} end)
  + (if $budget != "" then {thinking_budget: ($budget | tonumber)} else {} end)
  + (if $stream != "" then {stream: ($stream == "true")} else {} end)')

nia_post "$BASE_URL/document/agent" "$DATA"
