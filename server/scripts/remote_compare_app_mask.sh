#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: remote_compare_app_mask.sh IMAGE_PATH MASK_JSON_PATH" >&2
  exit 2
fi

PROJECT_DIR="${CRACK_PROJECT_DIR:-/home/crack/app/cloud_dev/crack_app_enterprise}"
LIVE_DIR="${CRACK_LIVE_DIR:-/home/crack/app/cloud_dev/live_stack}"
CLOUD_ENV_PYTHON="${CRACK_CLOUD_PYTHON:-/home/crack/app/cloud_dev/conda_envs/crack_cloud/bin/python}"

set -a
. "${LIVE_DIR}/.env"
set +a

export CRACK_LIVE_API_BASE="${CRACK_LIVE_API_BASE:-http://127.0.0.1:8000}"
export CRACK_KEYCLOAK_TOKEN_URL="${CRACK_KEYCLOAK_TOKEN_URL:-http://127.0.0.1:8080/realms/crack/protocol/openid-connect/token}"
export CRACK_KEYCLOAK_CLIENT_ID="${CRACK_KEYCLOAK_CLIENT_ID:-crack-app-mobile}"
export CRACK_KEYCLOAK_TEST_USER="${CRACK_KEYCLOAK_TEST_USER:-${KEYCLOAK_TEST_USER}}"
export CRACK_KEYCLOAK_TEST_PASSWORD="${CRACK_KEYCLOAK_TEST_PASSWORD:-${KEYCLOAK_TEST_PASSWORD}}"

"${CLOUD_ENV_PYTHON}" "${PROJECT_DIR}/server/scripts/compare_app_mask.py" \
  --image-path "$1" \
  --mask-path "$2"
