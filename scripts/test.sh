#!/usr/bin/env bash

set -euo pipefail

CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"

gateway_url=""

for attempt in $(seq 1 30); do

  gateway_json="$(
    curl --fail --silent \
      "${CONSUL_HTTP_ADDR}/v1/health/service/weather-gateway?passing=true"
  )"

  gateway_address="$(
    printf '%s' "${gateway_json}" \
      | jq -r '.[0].Service.Address // empty'
  )"

  gateway_port="$(
    printf '%s' "${gateway_json}" \
      | jq -r '.[0].Service.Port // empty'
  )"

  if [ -n "${gateway_address}" ] && [ -n "${gateway_port}" ]; then

    gateway_url="http://${gateway_address}:${gateway_port}"

    if curl --fail --silent \
      "${gateway_url}/health" \
      >/dev/null; then
      break
    fi
  fi

  if [ "${attempt}" -eq 30 ]; then
    echo "weather-gateway did not become healthy."
    exit 1
  fi

  sleep 2

done

curl --fail --silent --show-error \
  "${gateway_url}/health"

echo

curl --fail --silent --show-error \
  "${gateway_url}/api/weather/Ankara"

echo