#!/usr/bin/env bash
set -euo pipefail

# Simple health + entity inventory check for the minimal HA baseline.
# In CI we may start from a pristine config with no users/tokens. This script can:
# 1. Use an injected long-lived token (HA_CI_TOKEN) OR
# 2. Use a local file .ha_ci_token OR
# 3. Auto-complete onboarding, create a transient CI user, and obtain an access token (password grant)
#
# Auto-onboarding keeps the workflow self-contained and avoids leaking auth artifacts.

HA_URL="http://localhost:8123"
TOKEN_FILE=".ha_ci_token"

CI_USERNAME="${CI_HA_USERNAME:-ciuser}"
CI_PASSWORD="${CI_HA_PASSWORD:-cipass}"
CI_CLIENT_ID="http://localhost/"  # arbitrary but required for token grant

TOKEN=""

have_token_env=0
if [[ -n "${HA_CI_TOKEN:-}" ]]; then
  TOKEN="$HA_CI_TOKEN"
  have_token_env=1
elif [[ -f "$TOKEN_FILE" ]]; then
  TOKEN="$(< "$TOKEN_FILE")"
fi

wait_for_api() {
  echo "Waiting for Home Assistant API ..." >&2
  for i in {1..90}; do
    if curl -sf -o /dev/null "$HA_URL/api/"; then
      return 0
    fi
    sleep 2
  done
  echo "API root did not become ready in time" >&2
  return 1
}

onboarding_status() {
  curl -sf "$HA_URL/api/onboarding/status" || true
}

finish_onboarding_and_get_token() {
  echo "Attempting auto-onboarding (no token supplied) ..." >&2
  local status json onboarding
  status=$(onboarding_status)
  if [[ -z "$status" ]]; then
    echo "Could not fetch onboarding status" >&2
    return 1
  fi
  onboarding=$(echo "$status" | jq -r '.onboarding // empty') || true
  if [[ "$onboarding" != "true" ]]; then
    echo "Onboarding already completed; cannot auto-create user. Provide HA_CI_TOKEN instead." >&2
    return 1
  fi

  # Step 1: Create user
  curl -sf -X POST -H 'Content-Type: application/json' \
    -d "{\"name\":\"CI User\",\"username\":\"$CI_USERNAME\",\"password\":\"$CI_PASSWORD\"}" \
    "$HA_URL/api/onboarding/users" >/dev/null

  # Step 2: Core config (mirrors minimal config)
  curl -sf -X POST -H 'Content-Type: application/json' \
    -d '{"location_name":"Lab","language":"en","country":"NO","latitude":60.3913,"longitude":5.3221,"elevation":12,"unit_system":"metric","time_zone":"Europe/Oslo","currency":"NOK"}' \
    "$HA_URL/api/onboarding/core_config" >/dev/null

  # Step 3: Mark integrations step complete (Met will auto-add later)
  curl -sf -X POST -H 'Content-Type: application/json' -d '{"client_id":"'$CI_CLIENT_ID'"}' \
    "$HA_URL/api/onboarding/integration" >/dev/null

  # Obtain an access token (password grant)
  local token_json
  token_json=$(curl -sf -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "grant_type=password&username=$CI_USERNAME&password=$CI_PASSWORD&client_id=$CI_CLIENT_ID" \
    "$HA_URL/auth/token") || {
      echo "Failed to obtain auth token" >&2; return 1; }

  TOKEN=$(echo "$token_json" | jq -r '.access_token')
  if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "Access token parse failed" >&2
    return 1
  fi
  echo "Auto-onboarding succeeded; ephemeral access token acquired." >&2
}

ensure_token() {
  if [[ -n "$TOKEN" ]]; then
    return 0
  fi
  finish_onboarding_and_get_token || {
    echo "ERROR: No valid token available and auto-onboarding failed." >&2
    echo "Provide HA_CI_TOKEN (long-lived token) or allow auto-onboarding on a fresh config." >&2
    exit 1
  }
}

wait_for_api

ensure_token

echo "Fetching states ..." >&2
# Capture HTTP status to detect 401/other errors early
http_resp=$(mktemp)
status_code=$(curl -s -w "%{http_code}" -o "$http_resp" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$HA_URL/api/states" || true)
json="$(cat "$http_resp")"
rm -f "$http_resp"

if [[ "$status_code" != "200" ]]; then
  echo "ERROR: /api/states returned HTTP $status_code" >&2
  echo "Body: $json" >&2
  exit 1
fi

# Quick sanity that we have a JSON array
if ! echo "$json" | jq -e 'type=="array"' >/dev/null 2>&1; then
  echo "ERROR: Unexpected response (not a JSON array)" >&2
  echo "$json" | head -c 500 >&2
  exit 1
fi

# Basic sanity: JSON array and contains weather + light entity ids.
missing=0
require_entity() {
  local eid="$1"
  if ! echo "$json" | jq -e ".[] | select(.entity_id==\"$eid\")" >/dev/null; then
    echo "Missing expected entity: $eid" >&2
    missing=1
  fi
}

# Expected baseline custom entities
require_entity "light.lab_virtual_light"
require_entity "weather.forecast_home"

# Guard against old removed entities reappearing
for bad in input_boolean.lab_flag sensor.lab_magic_number automation.flip_lab_flag_every_minute automation.log_magic_number_every_5_minutes; do
  if echo "$json" | jq -e ".[] | select(.entity_id==\"$bad\")" >/dev/null; then
    echo "Found forbidden legacy entity: $bad" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "Entity inventory check FAILED" >&2
  exit 2
fi

echo "Entity inventory check PASSED" >&2

# If we auto-onboarded (no env token), print a hint (without leaking token)
if [[ $have_token_env -eq 0 ]]; then
  echo "(Ephemeral CI token used – not persisted)" >&2
fi
