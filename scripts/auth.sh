#!/usr/bin/env bash
# Nia Auth — programmatic signup and API key bootstrap/login
# Usage: auth.sh <command> [args...]
set -e

BASE_URL="https://apigcp.trynia.ai/v2"

request_raw() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-s -X "$method" "$BASE_URL$path")
  if [ -n "$data" ]; then
    args+=(-H "Content-Type: application/json" -d "$data")
  fi
  curl "${args[@]}"
}

save_api_key_if_requested() {
  local json="$1"
  if [ "${SAVE_KEY:-false}" != "true" ]; then
    return 0
  fi
  local api_key
  api_key=$(echo "$json" | jq -r '.api_key // empty')
  if [ -z "$api_key" ]; then
    return 0
  fi
  mkdir -p ~/.config/nia
  printf '%s\n' "$api_key" > ~/.config/nia/api_key
}

print_json() {
  echo "$1" | jq '.'
}

# ─── signup — create account and return bootstrap token
cmd_signup() {
  if [ -z "$3" ]; then
    echo "Usage: auth.sh signup <email> <password> <organization_name> [first_name] [last_name]"
    echo "  Env: IDEMPOTENCY_KEY"
    return 1
  fi
  DATA=$(jq -n \
    --arg email "$1" --arg password "$2" --arg org "$3" \
    --arg first "${4:-}" --arg last "${5:-}" --arg idem "${IDEMPOTENCY_KEY:-}" \
    '{email: $email, password: $password, organization_name: $org}
    + (if $first != "" then {first_name: $first} else {} end)
    + (if $last != "" then {last_name: $last} else {} end)
    + (if $idem != "" then {idempotency_key: $idem} else {} end)')
  print_json "$(request_raw POST /auth/signup "$DATA")"
}

# ─── bootstrap-key — exchange one-time bootstrap token for an nk_ API key
cmd_bootstrap_key() {
  if [ -z "$1" ]; then
    echo "Usage: auth.sh bootstrap-key <bootstrap_token>"
    echo "  Env: SAVE_KEY=true to write ~/.config/nia/api_key"
    return 1
  fi
  DATA=$(jq -n --arg token "$1" '{bootstrap_token: $token}')
  RESULT=$(request_raw POST /auth/bootstrap-key "$DATA")
  save_api_key_if_requested "$RESULT"
  print_json "$RESULT"
}

# ─── login-key — authenticate with email/password and mint a new API key
cmd_login_key() {
  if [ -z "$2" ]; then
    echo "Usage: auth.sh login-key <email> <password> [organization_id]"
    echo "  Env: SAVE_KEY=true, IDEMPOTENCY_KEY"
    return 1
  fi
  DATA=$(jq -n \
    --arg email "$1" --arg password "$2" --arg org "${3:-}" --arg idem "${IDEMPOTENCY_KEY:-}" \
    '{email: $email, password: $password}
    + (if $org != "" then {organization_id: $org} else {} end)
    + (if $idem != "" then {idempotency_key: $idem} else {} end)')
  RESULT=$(request_raw POST /auth/login-key "$DATA")
  save_api_key_if_requested "$RESULT"
  print_json "$RESULT"
}

# ─── dispatch ─────────────────────────────────────────────────────────────────
case "${1:-}" in
  signup)        shift; cmd_signup "$@" ;;
  bootstrap-key) shift; cmd_bootstrap_key "$@" ;;
  login-key)     shift; cmd_login_key "$@" ;;
  *)
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  signup         Create account and get bootstrap token"
    echo "  bootstrap-key  Exchange bootstrap token for nk_ API key"
    echo "  login-key      Mint a fresh API key with email/password"
    echo ""
    echo "Set SAVE_KEY=true to write the returned api_key to ~/.config/nia/api_key."
    exit 1
    ;;
esac
