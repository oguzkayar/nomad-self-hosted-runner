#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <job-name> <job-file> <image-tag>"
  exit 1
fi

JOB_NAME="$1"
JOB_FILE="$2"
IMAGE_TAG="$3"

echo "Deploying ${JOB_NAME}"
echo "Image tag: ${IMAGE_TAG}"

nomad job run \
  -detach \
  -var="image_tag=${IMAGE_TAG}" \
  "${JOB_FILE}"

echo "Job submitted. Waiting for deployment..."

for attempt in $(seq 1 60); do

  deployment_json="$(
    nomad job deployments \
      -latest \
      -json \
      "${JOB_NAME}"
  )"

  deployment_status="$(
    printf '%s' "${deployment_json}" |
      jq -r '
        if type == "array" then
          (.[0].Status // empty)
        else
          (.Status // empty)
        end
      '
  )"

  echo "Attempt ${attempt}/60: ${JOB_NAME} status=${deployment_status:-unknown}"

  case "${deployment_status}" in
    successful)
      echo "${JOB_NAME} deployment completed successfully."
      exit 0
      ;;

    failed|cancelled)
      echo "${JOB_NAME} deployment failed: ${deployment_status}"
      nomad job status "${JOB_NAME}" || true
      nomad job deployments "${JOB_NAME}" || true
      exit 1
      ;;

    *)
      sleep 2
      ;;
  esac
done

echo "Timed out waiting for ${JOB_NAME} deployment."
nomad job status "${JOB_NAME}" || true
nomad job deployments "${JOB_NAME}" || true
exit 1