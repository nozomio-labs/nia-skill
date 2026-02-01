#!/bin/bash
# List data sources: sources-list.sh [source_type]
# source_type: documentation | research_paper | huggingface_dataset
set -e
NIA_KEY=$(cat ~/.config/nia/api_key 2>/dev/null || echo "")
if [ -z "$NIA_KEY" ]; then echo "Error: No API key found"; exit 1; fi

SOURCE_TYPE="${1:-}"
URL="https://apigcp.trynia.ai/v2/data-sources"
if [ -n "$SOURCE_TYPE" ]; then
  URL="${URL}?source_type=${SOURCE_TYPE}"
fi

curl -s "$URL" \
  -H "Authorization: Bearer $NIA_KEY" | jq '.'
