#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <job-name> <job-file> <image-tag>"
  exit 1
fi

JOB_NAME="$1"
JOB_FILE="$2"
IMAGE_TAG="$3"

echo "Deploying Nomad job: ${JOB_NAME}"
echo "Job file: ${JOB_FILE}"
echo "Image tag: ${IMAGE_TAG}"

previous_deployment_id="$(
  nomad job status -json "${JOB_NAME}" 2>/dev/null \
    | jq -r '.LatestDeployment.ID // empty' || true
)"

echo "Previous deployment ID: ${previous_deployment_id:-none}"

nomad job run \
  -detach \
  -var="image_tag=${IMAGE_TAG}" \
  "${JOB_FILE}"

deployment_id=""

for (( attempt=1; attempt<=30; attempt++ )); do

  current_deployment_id="$(
    nomad job status -json "${JOB_NAME}" \
      | jq -r '.LatestDeployment.ID // empty'
  )"

  if [ -n "${current_deployment_id}" ] && \
     [ "${current_deployment_id}" != "${previous_deployment_id}" ]; then

    deployment_id="${current_deployment_id}"
    break
  fi

  sleep 1

done

if [ -z "${deployment_id}" ]; then
  echo "Could not determine new deployment ID for ${JOB_NAME}."
  exit 1
fi

echo "Deployment ID: ${deployment_id}"

for (( attempt=1; attempt<=60; attempt++ )); do

  deployment_status="$(
    nomad deployment status -json "${deployment_id}" \
      | jq -r '.Status'
  )"

  echo "${JOB_NAME} deployment status: ${deployment_status}"

  case "${deployment_status}" in

    successful)
      echo "${JOB_NAME} deployment completed successfully."
      exit 0
      ;;

    failed|cancelled)
      echo "${JOB_NAME} deployment failed with status: ${deployment_status}"

      nomad deployment status "${deployment_id}" || true

      exit 1
      ;;

    *)
      sleep 2
      ;;

  esac

done

echo "Timed out waiting for ${JOB_NAME} deployment."

nomad deployment status "${deployment_id}" || true

exit 1
