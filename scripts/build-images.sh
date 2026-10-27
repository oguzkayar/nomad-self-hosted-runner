#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE_TAG="${1:-1.0}"

BUILD_ARGS=(
  --pull
)

if [ -n "${GITHUB_SHA:-}" ]; then
  BUILD_ARGS+=(
    --label "org.opencontainers.image.revision=${GITHUB_SHA}"
  )
fi

echo "Building weather-service:${IMAGE_TAG}..."

docker build \
  "${BUILD_ARGS[@]}" \
  --target weather-service \
  --tag "nomad-weather-service:${IMAGE_TAG}" \
  "$ROOT_DIR"

echo "Building weather-gateway:${IMAGE_TAG}..."

docker build \
  "${BUILD_ARGS[@]}" \
  --target weather-gateway \
  --tag "nomad-weather-gateway:${IMAGE_TAG}" \
  "$ROOT_DIR"

echo
echo "Images created successfully:"

docker image inspect \
  "nomad-weather-service:${IMAGE_TAG}" \
  >/dev/null

docker image inspect \
  "nomad-weather-gateway:${IMAGE_TAG}" \
  >/dev/null

docker image ls \
  --filter reference='nomad-weather-*'