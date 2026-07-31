#!/usr/bin/env bash

set -euo pipefail

CONSUL_HTTP_ADDR="${CONSUL_HTTP_ADDR:-http://127.0.0.1:8500}"

gateway_url=""

for attempt in $(seq 1 30); do

  echo "Discovering weather-gateway: attempt ${attempt}/30"

  gateway_json="$(
    curl \
      --fail \
      --silent \
      --show-error \
      --connect-timeout 3 \
      --max-time 10 \
      "${CONSUL_HTTP_ADDR}/v1/health/service/weather-gateway?passing=true"
  )"

  gateway_address="$(
    printf '%s' "${gateway_json}" |
      jq -r '.[0].Service.Address // empty'
  )"

  gateway_port="$(
    printf '%s' "${gateway_json}" |
      jq -r '.[0].Service.Port // empty'
  )"

  if [ -n "${gateway_address}" ] && [ -n "${gateway_port}" ]; then
    gateway_url="http://${gateway_address}:${gateway_port}"

    echo "Testing Gateway: ${gateway_url}/health"

    if curl \
      --fail \
      --silent \
      --show-error \
      --connect-timeout 3 \
      --max-time 10 \
      "${gateway_url}/health" \
      >/dev/null; then

      echo "Gateway is healthy."
      break
    fi
  fi

  if [ "${attempt}" -eq 30 ]; then
    echo "weather-gateway did not become reachable."
    exit 1
  fi

  sleep 2
done

echo "Testing Gateway health..."

curl \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 3 \
  --max-time 10 \
  "${gateway_url}/health"

echo

echo "Testing weather endpoint..."

curl \
  --fail \
  --silent \
  --show-error \
  --connect-timeout 3 \
  --max-time 15 \
  "${gateway_url}/api/weather/Ankara"

echo
echo "Smoke test completed successfully."