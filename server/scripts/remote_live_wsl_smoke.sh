#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CRACK_PROJECT_DIR:-/home/crack/app/cloud_dev/crack_app_enterprise}"
LIVE_DIR="${CRACK_LIVE_DIR:-/home/crack/app/cloud_dev/live_stack}"
CLOUD_ENV_PYTHON="${CRACK_CLOUD_PYTHON:-/home/crack/app/cloud_dev/conda_envs/crack_cloud/bin/python}"
IMAGE_PATH="${CRACK_LIVE_IMAGE_PATH:-/home/crack/app/cloud_dev/crackscan_inputs_manual/1.jpg}"

cd "${PROJECT_DIR}"
set -a
. "${LIVE_DIR}/.env"
set +a

export PYTHONPATH="${PROJECT_DIR}"
export CRACK_LIVE_API_BASE="${CRACK_LIVE_API_BASE:-http://127.0.0.1:8000}"
export CRACK_KEYCLOAK_TOKEN_URL="${CRACK_KEYCLOAK_TOKEN_URL:-http://127.0.0.1:8080/realms/crack/protocol/openid-connect/token}"
export CRACK_KEYCLOAK_CLIENT_ID="${CRACK_KEYCLOAK_CLIENT_ID:-crack-app-mobile}"
export CRACK_KEYCLOAK_TEST_USER="${CRACK_KEYCLOAK_TEST_USER:-${KEYCLOAK_TEST_USER}}"
export CRACK_KEYCLOAK_TEST_PASSWORD="${CRACK_KEYCLOAK_TEST_PASSWORD:-${KEYCLOAK_TEST_PASSWORD}}"
export CRACK_LIVE_IMAGE_PATH="${IMAGE_PATH}"
export CRACK_LIVE_TIMEOUT_SECONDS="${CRACK_LIVE_TIMEOUT_SECONDS:-900}"

"${CLOUD_ENV_PYTHON}" server/scripts/live_smoke.py 2>&1 \
  | tee /home/crack/app/cloud_dev/live_smoke_last.log
