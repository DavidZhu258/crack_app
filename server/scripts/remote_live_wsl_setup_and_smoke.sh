#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CRACK_PROJECT_DIR:-/home/crack/app/cloud_dev/crack_app_enterprise}"

bash "${PROJECT_DIR}/server/scripts/remote_live_wsl_setup.sh"
sleep "${CRACK_LIVE_POST_SETUP_WAIT_SECONDS:-20}"
bash "${PROJECT_DIR}/server/scripts/remote_live_wsl_smoke.sh"
