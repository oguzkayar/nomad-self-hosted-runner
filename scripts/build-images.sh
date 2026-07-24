#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

docker build -t nomad-weather-service:1.0 "$ROOT_DIR/weather-service"
docker build -t nomad-weather-gateway:1.0 "$ROOT_DIR/weather-gateway"

echo
echo "Oluşturulan imajlar:"
docker image ls --filter reference='nomad-weather-*'
