#!/usr/bin/env bash
# Nia Search — query, web, deep, universal
# Usage: search.sh <command> [args...]
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

csv_to_json_array() {
  local csv="${1:-}" result="[]"
  while IFS= read -r raw; do
    local item
    item=$(nia_trim "$raw")
    [ -z "$item" ] && continue
    result=$(echo "$result" | jq --arg item "$item" '. + [$item]')
  done < <(printf '%s\n' "$csv" | tr ',' '\n')
  echo "$result"
}

resolve_query_repositories() {
  local repos_csv="${1:-}" result="[]"
  local resolve_ids="${RESOLVE_SOURCE_IDS:-true}" require_ready="${REQUIRE_INDEXED_REPOS:-true}"
  local -a skipped_repos=()
  while IFS= read -r raw; do
    local repo target resolved source_json source_status
    repo=$(nia_trim "$raw")
    [ -z "$repo" ] && continue
    target="$repo"
    if [ "$resolve_ids" = "true" ]; then
      resolved=$(resolve_source_id "$repo" repository || true)
      if [ -n "$resolved" ]; then target="$resolved"; fi
    fi
    if [ "$require_ready" = "true" ] && nia_is_source_id "$target"; then
      source_json=$(nia_curl GET "$BASE_URL/sources/${target}?type=repository")
      if echo "$source_json" | jq -e '.error?' >/dev/null 2>&1; then
        echo "Warning: Could not verify indexing status for repository '$repo'; continuing." >&2
      elif ! nia_source_is_ready "$source_json"; then
        source_status=$(nia_source_status_label "$source_json")
        skipped_repos+=("$repo (${source_status:-unknown})")
        continue
      fi
    fi
    result=$(echo "$result" | jq --arg item "$target" '. + [$item]')
  done < <(printf '%s\n' "$repos_csv" | tr ',' '\n')
  if [ "${#skipped_repos[@]}" -gt 0 ]; then
    echo "Warning: Skipping repositories not ready for semantic search: ${skipped_repos[*]}" >&2
  fi
  echo "$result"
}

resolve_query_sources() {
  local sources_csv="${1:-}" result="[]"
  local resolve_ids="${RESOLVE_SOURCE_IDS:-true}"
  while IFS= read -r raw; do
    local source target resolved
    source=$(nia_trim "$raw")
    [ -z "$source" ] && continue
    target="$source"
    if [ "$resolve_ids" = "true" ]; then
      resolved=$(resolve_source_id "$source" || true)
      if [ -n "$resolved" ]; then target="$resolved"; fi
    fi
    result=$(echo "$result" | jq --arg item "$target" '. + [$item]')
  done < <(printf '%s\n' "$sources_csv" | tr ',' '\n')
  echo "$result"
}

# ─── query — AI-powered search across specific repos, docs, or local folders
cmd_query() {
  if [ -z "$1" ]; then
    echo "Usage: search.sh query <query> <repos_csv> [docs_csv]"
    echo "  Env: LOCAL_FOLDERS, SLACK_WORKSPACES, CATEGORY, MAX_TOKENS,"
    echo "       FAST_MODE, SKIP_LLM, REASONING_STRATEGY, MODEL,"
    echo "       BYPASS_CACHE, INCLUDE_FOLLOW_UPS, RESOLVE_SOURCE_IDS,"
    echo "       REQUIRE_INDEXED_REPOS"
    echo "  Slack filter env: SLACK_CHANNELS, SLACK_USERS, SLACK_DATE_FROM,"
    echo "       SLACK_DATE_TO, SLACK_INCLUDE_THREADS"
    return 1
  fi
  local query="$1" repos="${2:-}" docs="${3:-}"
  if [ -n "$repos" ]; then
    REPOS_JSON=$(resolve_query_repositories "$repos")
  else REPOS_JSON="[]"; fi
  if [ -n "$docs" ]; then
    DOCS_JSON=$(resolve_query_sources "$docs")
  else DOCS_JSON="[]"; fi
  if [ -n "${LOCAL_FOLDERS:-}" ]; then
    FOLDERS_JSON=$(csv_to_json_array "$LOCAL_FOLDERS")
  else FOLDERS_JSON="[]"; fi
  if [ -n "${SLACK_WORKSPACES:-}" ]; then
    SLACK_JSON=$(csv_to_json_array "$SLACK_WORKSPACES")
  else SLACK_JSON="[]"; fi
  local repos_len docs_len folders_len slack_len
  repos_len=$(echo "$REPOS_JSON" | jq 'length')
  docs_len=$(echo "$DOCS_JSON" | jq 'length')
  folders_len=$(echo "$FOLDERS_JSON" | jq 'length')
  slack_len=$(echo "$SLACK_JSON" | jq 'length')
  if [ "$repos_len" -eq 0 ] && [ "$docs_len" -eq 0 ] && [ "$folders_len" -eq 0 ] && [ "$slack_len" -eq 0 ]; then
    jq -n --arg msg "No query targets are ready. Wait for indexing to finish or disable REQUIRE_INDEXED_REPOS." '{error: $msg}'
    return 1
  fi
  # Build slack_filters if any slack filter env is set
  SLACK_FILTERS="null"
  if [ -n "${SLACK_CHANNELS:-}${SLACK_USERS:-}${SLACK_DATE_FROM:-}${SLACK_DATE_TO:-}${SLACK_INCLUDE_THREADS:-}" ]; then
    SLACK_FILTERS=$(jq -n \
      --arg ch "${SLACK_CHANNELS:-}" --arg us "${SLACK_USERS:-}" \
      --arg df "${SLACK_DATE_FROM:-}" --arg dt "${SLACK_DATE_TO:-}" \
      --arg it "${SLACK_INCLUDE_THREADS:-}" \
      '{}
      + (if $ch != "" then {channels: ($ch | split(","))} else {} end)
      + (if $us != "" then {users: ($us | split(","))} else {} end)
      + (if $df != "" then {date_from: $df} else {} end)
      + (if $dt != "" then {date_to: $dt} else {} end)
      + (if $it != "" then {include_threads: ($it == "true")} else {} end)')
  fi
  # Auto-detect search mode
  if [ "$repos_len" -gt 0 ] && [ "$docs_len" -eq 0 ]; then MODE="repositories"
  elif [ "$repos_len" -eq 0 ] && [ "$docs_len" -gt 0 ]; then MODE="sources"
  else MODE="unified"; fi
  DATA=$(jq -n \
    --arg q "$query" --arg mode "$MODE" \
    --argjson repos "$REPOS_JSON" --argjson docs "$DOCS_JSON" \
    --argjson folders "$FOLDERS_JSON" --argjson slack "$SLACK_JSON" \
    --argjson slack_filters "$SLACK_FILTERS" \
    --arg cat "${CATEGORY:-}" --arg mt "${MAX_TOKENS:-}" \
    --arg fast "${FAST_MODE:-}" --arg skip "${SKIP_LLM:-}" \
    --arg rs "${REASONING_STRATEGY:-}" --arg model "${MODEL:-}" \
    --arg bc "${BYPASS_CACHE:-}" --arg ifu "${INCLUDE_FOLLOW_UPS:-}" \
    '{mode: "query", messages: [{role: "user", content: $q}], repositories: $repos,
     data_sources: $docs, search_mode: $mode, stream: false, include_sources: true}
    + (if ($folders | length) > 0 then {local_folders: $folders} else {} end)
    + (if ($slack | length) > 0 then {slack_workspaces: $slack} else {} end)
    + (if $slack_filters != null then {slack_filters: $slack_filters} else {} end)
    + (if $cat != "" then {category: $cat} else {} end)
    + (if $mt != "" then {max_tokens: ($mt | tonumber)} else {} end)
    + (if $fast != "" then {fast_mode: ($fast == "true")} else {} end)
    + (if $skip != "" then {skip_llm: ($skip == "true")} else {} end)
    + (if $rs != "" then {reasoning_strategy: $rs} else {} end)
    + (if $model != "" then {model: $model} else {} end)
    + (if $bc != "" then {bypass_semantic_cache: ($bc == "true")} else {} end)
    + (if $ifu != "" then {include_follow_ups: ($ifu == "true")} else {} end)')
  nia_post "$BASE_URL/search" "$DATA"
}

# ─── web — search the public web, filterable by category and recency
cmd_web() {
  if [ -z "$1" ]; then
    echo "Usage: search.sh web <query> [num_results]"
    echo "  Env: CATEGORY (github|company|research|news|tweet|pdf|blog), DAYS_BACK, FIND_SIMILAR_TO"
    return 1
  fi
  DATA=$(jq -n \
    --arg q "$1" --argjson n "${2:-5}" \
    --arg cat "${CATEGORY:-}" --arg days "${DAYS_BACK:-}" --arg sim "${FIND_SIMILAR_TO:-}" \
    '{mode: "web", query: $q, num_results: $n}
    + (if $cat != "" then {category: $cat} else {} end)
    + (if $days != "" then {days_back: ($days | tonumber)} else {} end)
    + (if $sim != "" then {find_similar_to: $sim} else {} end)')
  nia_post "$BASE_URL/search" "$DATA"
}

# ─── deep — deep AI research that synthesizes multiple web sources (Pro)
cmd_deep() {
  if [ -z "$1" ]; then
    echo "Usage: search.sh deep <query> [output_format]"
    echo "  Env: VERBOSE=true for trace output"
    return 1
  fi
  DATA=$(jq -n \
    --arg q "$1" --arg fmt "${2:-}" --arg verbose "${VERBOSE:-}" \
    '{mode: "deep", query: $q}
    + (if $fmt != "" then {output_format: $fmt} else {} end)
    + (if $verbose == "true" then {verbose: true} else {} end)')
  nia_post "$BASE_URL/search" "$DATA"
}

# ─── universal — hybrid semantic+keyword search across all your indexed sources
cmd_universal() {
  if [ -z "$1" ]; then
    echo "Usage: search.sh universal <query> [top_k]"
    echo "  Env: INCLUDE_REPOS, INCLUDE_DOCS, INCLUDE_HF, ALPHA, COMPRESS,"
    echo "       MAX_TOKENS, BOOST_LANGUAGES, LANGUAGE_BOOST, EXPAND_SYMBOLS, NATIVE_BOOSTING"
    return 1
  fi
  DATA=$(jq -n \
    --arg q "$1" --argjson k "${2:-20}" \
    --arg ir "${INCLUDE_REPOS:-true}" --arg id "${INCLUDE_DOCS:-true}" \
    --arg ihf "${INCLUDE_HF:-}" --arg alpha "${ALPHA:-}" \
    --arg compress "${COMPRESS:-false}" --arg mt "${MAX_TOKENS:-}" \
    --arg bl "${BOOST_LANGUAGES:-}" --arg lbf "${LANGUAGE_BOOST:-}" \
    --arg es "${EXPAND_SYMBOLS:-}" --arg nb "${NATIVE_BOOSTING:-}" \
    '{mode: "universal", query: $q, top_k: $k,
     include_repos: ($ir == "true"), include_docs: ($id == "true"),
     compress_output: ($compress == "true")}
    + (if $ihf != "" then {include_huggingface_datasets: ($ihf == "true")} else {} end)
    + (if $alpha != "" then {alpha: ($alpha | tonumber)} else {} end)
    + (if $mt != "" then {max_tokens: ($mt | tonumber)} else {} end)
    + (if $bl != "" then {boost_languages: ($bl | split(","))} else {} end)
    + (if $lbf != "" then {language_boost_factor: ($lbf | tonumber)} else {} end)
    + (if $es != "" then {expand_symbols: ($es == "true")} else {} end)
    + (if $nb != "" then {use_native_boosting: ($nb == "true")} else {} end)')
  nia_post "$BASE_URL/search" "$DATA"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  query)     shift; cmd_query "$@" ;;
  web)       shift; cmd_web "$@" ;;
  deep)      shift; cmd_deep "$@" ;;
  universal) shift; cmd_universal "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  query      Query specific repos/sources with AI"
    echo "  web        Web search"
    echo "  deep       Deep research (Pro only)"
    echo "  universal  Search across all public indexed sources"
    exit 1
    ;;
esac
