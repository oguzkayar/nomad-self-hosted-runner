#!/usr/bin/env bash
set -euo pipefail

nomad job stop -purge weather-gateway || true
nomad job stop -purge weather-service || true
