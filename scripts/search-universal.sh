#!/bin/bash
# Universal search across all indexed sources: search-universal.sh "query" [top_k]
set -e
NIA_KEY=$(cat ~/.config/nia/api_key 2>/dev/null || echo "")
if [ -z "$NIA_KEY" ]; then echo "Error: No API key found"; exit 1; fi
if [ -z "$1" ]; then echo "Usage: search-universal.sh 'query' [top_k]"; exit 1; fi

QUERY="$1"
TOP_K="${2:-20}"

DATA=$(jq -n --arg q "$QUERY" --argjson k "$TOP_K" '{query: $q, top_k: $k, compress_output: false}')

curl -s -X POST "https://apigcp.trynia.ai/v2/search/universal" \
  -H "Authorization: Bearer $NIA_KEY" \
  -H "Content-Type: application/json" \
  -d "$DATA" | jq '.'
