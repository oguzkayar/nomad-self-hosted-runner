#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_TAG="${1:-1.0}"

nomad job validate -var="image_tag=${IMAGE_TAG}" "$ROOT_DIR/nomad/weather-service.nomad.hcl"
nomad job validate -var="image_tag=${IMAGE_TAG}" "$ROOT_DIR/nomad/weather-gateway.nomad.hcl"

nomad job run -var="image_tag=${IMAGE_TAG}" "$ROOT_DIR/nomad/weather-service.nomad.hcl"
nomad job run -var="image_tag=${IMAGE_TAG}" "$ROOT_DIR/nomad/weather-gateway.nomad.hcl"
