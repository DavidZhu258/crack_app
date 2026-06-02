#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${CRACK_PROJECT_DIR:-/home/crack/app/cloud_dev/crack_app_enterprise}"
LIVE_DIR="${CRACK_LIVE_DIR:-/home/crack/app/cloud_dev/live_stack}"
CLOUD_ENV_PYTHON="${CRACK_CLOUD_PYTHON:-/home/crack/app/cloud_dev/conda_envs/crack_cloud/bin/python}"
API_PID_FILE="/home/crack/app/cloud_dev/crack_fastapi_live.pid"
API_LOG_FILE="/home/crack/app/cloud_dev/crack_fastapi_live.log"

ensure_host_tools() {
  missing=()
  for tool in curl openssl; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      missing+=("${tool}")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    apt-get update
    apt-get install -y ca-certificates curl openssl
  fi
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

start_docker() {
  if docker info >/dev/null 2>&1; then
    return
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl start docker >/dev/null 2>&1 || true
  fi
  if ! docker info >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then
    service docker start >/dev/null 2>&1 || true
  fi
  if ! docker info >/dev/null 2>&1; then
    nohup dockerd >/home/crack/app/cloud_dev/dockerd.log 2>&1 &
    sleep 5
  fi
  docker info >/dev/null
}

rand_hex() {
  openssl rand -hex 16
}

prepare_live_dir() {
  mkdir -p "${LIVE_DIR}"
  cp "${PROJECT_DIR}/server/deploy/live/docker-compose.yml" "${LIVE_DIR}/docker-compose.yml"
  cp "${PROJECT_DIR}/server/deploy/live/keycloak-realm.json" "${LIVE_DIR}/keycloak-realm.json"
  if [ ! -f "${LIVE_DIR}/.env" ]; then
    umask 077
    cat > "${LIVE_DIR}/.env" <<ENV
MYSQL_ROOT_PASSWORD=$(rand_hex)
MYSQL_IMAGE=quay.io/sclorg/mysql-84-c9s
KEYCLOAK_DB_PASSWORD=$(rand_hex)
CRACK_DB_NAME=crack_app
CRACK_DB_USERNAME=crack_app
CRACK_DB_PASSWORD=$(rand_hex)
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(rand_hex)
KEYCLOAK_TEST_USER=miner01
KEYCLOAK_TEST_PASSWORD=$(rand_hex)
MINIO_ROOT_USER=crackminio
MINIO_ROOT_PASSWORD=$(rand_hex)
MINIO_BUCKET=crack-record-assets
ENV
  fi
}

start_live_stack() {
  cd "${LIVE_DIR}"
  set -a
  . "${LIVE_DIR}/.env"
  set +a
  docker compose up -d mysql minio
  for _ in $(seq 1 90); do
    if docker compose exec -T mysql \
      mysqladmin ping --protocol=TCP -h 127.0.0.1 \
      -ukeycloak -p"${KEYCLOAK_DB_PASSWORD}" --silent >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done
  docker compose exec -T mysql \
    mysqladmin ping --protocol=TCP -h 127.0.0.1 \
    -ukeycloak -p"${KEYCLOAK_DB_PASSWORD}" --silent >/dev/null
  sql_file="$(mktemp)"
  cat > "${sql_file}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${CRACK_DB_NAME}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER IF NOT EXISTS '${CRACK_DB_USERNAME}'@'%'
  IDENTIFIED BY '${CRACK_DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${CRACK_DB_NAME}\`.* TO '${CRACK_DB_USERNAME}'@'%';
FLUSH PRIVILEGES;
SQL
  if docker compose exec -T mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" \
      < "${sql_file}" >/tmp/crack_mysql_init_primary.log 2>&1; then
    rm -f "${sql_file}"
  elif docker compose exec -T mysql mysql -uroot \
      < "${sql_file}" >/tmp/crack_mysql_init_fallback.log 2>&1; then
    rm -f "${sql_file}"
  else
    rm -f "${sql_file}"
    cat /tmp/crack_mysql_init_primary.log /tmp/crack_mysql_init_fallback.log >&2 || true
    echo "[ERROR] failed to initialize crack_app database" >&2
    exit 1
  fi
  echo "[OK] crack_app database user is ready"
  docker compose up -d keycloak
  setup_minio_bucket
  setup_keycloak_user
  docker compose ps
}

setup_minio_bucket() {
  docker run --rm \
    --network crack-enterprise-live_default \
    --entrypoint /bin/sh \
    -e MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
    -e MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
    -e MINIO_BUCKET="${MINIO_BUCKET}" \
    quay.io/minio/mc:latest \
    -ec '
      until mc alias set local http://minio:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; do
        sleep 2
      done
      mc mb --ignore-existing "local/${MINIO_BUCKET}"
      mc anonymous set none "local/${MINIO_BUCKET}"
      echo "[OK] MinIO bucket is ready"
    '
}

setup_keycloak_user() {
  docker run --rm \
    --network crack-enterprise-live_default \
    --entrypoint /bin/bash \
    -e KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN}" \
    -e KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}" \
    -e KEYCLOAK_TEST_USER="${KEYCLOAK_TEST_USER}" \
    -e KEYCLOAK_TEST_PASSWORD="${KEYCLOAK_TEST_PASSWORD}" \
    quay.io/keycloak/keycloak:26.0 \
    -ec '
      until /opt/keycloak/bin/kcadm.sh config credentials \
          --server http://keycloak:8080 \
          --realm master \
          --user "${KEYCLOAK_ADMIN}" \
          --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null 2>&1; do
        sleep 5
      done
      user_id="$(/opt/keycloak/bin/kcadm.sh get users -r crack \
        -q username="${KEYCLOAK_TEST_USER}" \
        --fields id --format csv --noquotes | tail -n 1)"
      if [ -z "${user_id}" ]; then
        /opt/keycloak/bin/kcadm.sh create users -r crack \
          -s username="${KEYCLOAK_TEST_USER}" \
          -s email="${KEYCLOAK_TEST_USER}@example.local" \
          -s emailVerified=true \
          -s firstName=Smoke \
          -s lastName=Operator \
          -s "requiredActions=[]" \
          -s enabled=true
        user_id="$(/opt/keycloak/bin/kcadm.sh get users -r crack \
          -q username="${KEYCLOAK_TEST_USER}" \
          --fields id --format csv --noquotes | tail -n 1)"
      fi
      /opt/keycloak/bin/kcadm.sh update "users/${user_id}" -r crack \
        -s enabled=true \
        -s email="${KEYCLOAK_TEST_USER}@example.local" \
        -s emailVerified=true \
        -s firstName=Smoke \
        -s lastName=Operator \
        -s "requiredActions=[]"
      /opt/keycloak/bin/kcadm.sh set-password -r crack \
        --username "${KEYCLOAK_TEST_USER}" \
        --new-password "${KEYCLOAK_TEST_PASSWORD}" \
        --temporary=false
      /opt/keycloak/bin/kcadm.sh add-roles -r crack \
        --uusername "${KEYCLOAK_TEST_USER}" \
        --rolename operator || true
      echo "[OK] Keycloak smoke-test user is ready"
    '
}

apply_mysql_schema() {
  cd "${LIVE_DIR}"
  set -a
  . "${LIVE_DIR}/.env"
  set +a
  docker compose exec -T mysql \
    mysql -h 127.0.0.1 -u"${CRACK_DB_USERNAME}" -p"${CRACK_DB_PASSWORD}" "${CRACK_DB_NAME}" \
    < "${PROJECT_DIR}/server/db/mysql_schema.sql"
}

start_fastapi() {
  cd "${PROJECT_DIR}"
  set -a
  . "${LIVE_DIR}/.env"
  set +a
  if [ -f "${API_PID_FILE}" ]; then
    kill "$(cat "${API_PID_FILE}")" >/dev/null 2>&1 || true
    rm -f "${API_PID_FILE}"
  fi
  pkill -f "uvicorn server.app.main:app.*127.0.0.1.*8000" >/dev/null 2>&1 || true
  nohup env \
    PYTHONPATH="${PROJECT_DIR}" \
    CRACK_AUTH_DISABLED=false \
    CRACK_OIDC_ISSUER=http://127.0.0.1:8080/realms/crack \
    CRACK_OIDC_AUDIENCE=crack-app-api \
    CRACK_RECORD_STORE=mysql \
    "CRACK_MYSQL_DSN=mysql+pymysql://${CRACK_DB_USERNAME}:${CRACK_DB_PASSWORD}@127.0.0.1:3306/${CRACK_DB_NAME}?charset=utf8mb4" \
    CRACK_S3_ENDPOINT_URL=http://127.0.0.1:9000 \
    CRACK_OBJECT_PUBLIC_ENDPOINT=http://127.0.0.1:9000 \
    CRACK_S3_ACCESS_KEY_ID="${MINIO_ROOT_USER}" \
    CRACK_S3_SECRET_ACCESS_KEY="${MINIO_ROOT_PASSWORD}" \
    CRACK_OBJECT_BUCKET="${MINIO_BUCKET}" \
    CRACK_INFERENCE_BACKEND=crackscan \
    CRACK_MAX_MASK_PIXELS="${CRACK_MAX_MASK_PIXELS:-50000}" \
    CRACK_CRACKSCAN_OUTPUT_BASE_DIR=/home/crack/app/cloud_dev/crackscan_results \
    CRACK_CRACKSCAN_INPUT_DIR=/home/crack/app/cloud_dev/crackscan_inputs \
    "${CLOUD_ENV_PYTHON}" -m uvicorn server.app.main:app --host 127.0.0.1 --port 8000 \
    > "${API_LOG_FILE}" 2>&1 &
  echo "$!" > "${API_PID_FILE}"

  for _ in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8000/health >/dev/null 2>&1; then
      echo "[OK] FastAPI is ready"
      return
    fi
    sleep 2
  done
  tail -n 120 "${API_LOG_FILE}" || true
  echo "[ERROR] FastAPI did not become ready" >&2
  exit 1
}

ensure_host_tools
install_docker_if_needed
start_docker
prepare_live_dir
start_live_stack
apply_mysql_schema
start_fastapi
echo "[OK] live stack setup completed"
