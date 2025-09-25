#!/usr/bin/env bash
set -euo pipefail

# Simple health + entity inventory check for the minimal HA baseline.
# Requires: docker compose, curl, jq. HA must already be up (the workflow ensures this).

HA_URL="http://localhost:8123"
TOKEN_FILE=".ha_ci_token"

# The workflow will inject a long-lived token as HA_CI_TOKEN env var (preferred),
# but for local dev you can drop one into .ha_ci_token (not committed).
if [[ -n "${HA_CI_TOKEN:-}" ]]; then
  TOKEN="$HA_CI_TOKEN"
elif [[ -f "$TOKEN_FILE" ]]; then
  TOKEN="$(< "$TOKEN_FILE")"
else
  echo "ERROR: No token provided. Set HA_CI_TOKEN env var (recommended) or create .ha_ci_token." >&2
  exit 1
fi

wait_for_api() {
  echo "Waiting for Home Assistant API ..." >&2
  for i in {1..60}; do
    if curl -s -o /dev/null "$HA_URL/api/config"; then
      return 0
    fi
    sleep 2
  done
  echo "API did not become ready in time" >&2
  return 1
}

wait_for_api

echo "Fetching states ..." >&2
json=$(curl -s -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$HA_URL/api/states")

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
