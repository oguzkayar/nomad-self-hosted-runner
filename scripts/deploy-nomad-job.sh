#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <job-name> <job-file> <image-tag>"
  exit 1
fi

JOB_NAME="$1"
JOB_FILE="$2"
IMAGE_TAG="$3"

NOMAD_ADDR="${NOMAD_ADDR:-http://127.0.0.1:4646}"

DEPLOYMENT_DISCOVERY_ATTEMPTS="${DEPLOYMENT_DISCOVERY_ATTEMPTS:-30}"
DEPLOYMENT_STATUS_ATTEMPTS="${DEPLOYMENT_STATUS_ATTEMPTS:-60}"
DEPLOYMENT_STATUS_INTERVAL_SECONDS="${DEPLOYMENT_STATUS_INTERVAL_SECONDS:-2}"

get_latest_deployment_id() {
  local response
  local http_status
  local response_file

  response_file="$(mktemp)"

  http_status="$(
    curl \
      --silent \
      --show-error \
      --output "${response_file}" \
      --write-out '%{http_code}' \
      "${NOMAD_ADDR}/v1/job/${JOB_NAME}/deployment"
  )"

  case "${http_status}" in
    200)
      response="$(cat "${response_file}")"
      rm -f "${response_file}"

      printf '%s' "${response}" |
        jq -r '.ID // empty'
      ;;

    404)
      rm -f "${response_file}"
      printf ''
      ;;

    *)
      echo "Could not query the latest deployment for ${JOB_NAME}." >&2
      echo "Nomad returned HTTP ${http_status}." >&2
      cat "${response_file}" >&2 || true
      rm -f "${response_file}"
      return 1
      ;;
  esac
}

show_diagnostics() {
  echo
  echo "Nomad diagnostics for ${JOB_NAME}:"

  nomad job status "${JOB_NAME}" || true
  nomad job status -evals "${JOB_NAME}" || true
  nomad job allocs "${JOB_NAME}" || true
}

echo "Deploying Nomad job: ${JOB_NAME}"
echo "Job file: ${JOB_FILE}"
echo "Image tag: ${IMAGE_TAG}"
echo "Nomad address: ${NOMAD_ADDR}"

previous_deployment_id="$(get_latest_deployment_id)"

echo "Previous deployment ID: ${previous_deployment_id:-none}"

nomad job run \
  -detach \
  -var="image_tag=${IMAGE_TAG}" \
  "${JOB_FILE}"

deployment_id=""

for ((attempt = 1; attempt <= DEPLOYMENT_DISCOVERY_ATTEMPTS; attempt++)); do
  current_deployment_id="$(get_latest_deployment_id)"

  if [ -n "${current_deployment_id}" ] &&
     [ "${current_deployment_id}" != "${previous_deployment_id}" ]; then
    deployment_id="${current_deployment_id}"
    break
  fi

  echo "Waiting for a new ${JOB_NAME} deployment..."
  sleep 1
done

if [ -z "${deployment_id}" ]; then
  echo "Could not determine the new deployment ID for ${JOB_NAME}."
  show_diagnostics
  exit 1
fi

echo "New deployment ID: ${deployment_id}"

for ((attempt = 1; attempt <= DEPLOYMENT_STATUS_ATTEMPTS; attempt++)); do
  deployment_status="$(
    nomad deployment status \
      -json \
      "${deployment_id}" |
      jq -r '.Status // empty'
  )"

  echo "${JOB_NAME} deployment status: ${deployment_status:-unknown}"

  case "${deployment_status}" in
    successful)
      echo "${JOB_NAME} deployment completed successfully."
      exit 0
      ;;

    failed|cancelled)
      echo "${JOB_NAME} deployment ended with status: ${deployment_status}"
      nomad deployment status "${deployment_id}" || true
      show_diagnostics
      exit 1
      ;;

    running|pending|initializing|paused|"")
      sleep "${DEPLOYMENT_STATUS_INTERVAL_SECONDS}"
      ;;

    *)
      echo "Unexpected deployment status: ${deployment_status}"
      sleep "${DEPLOYMENT_STATUS_INTERVAL_SECONDS}"
      ;;
  esac
done

echo "Timed out waiting for ${JOB_NAME} deployment."
nomad deployment status "${deployment_id}" || true
show_diagnostics
exit 1