#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: ensure_site.sh <command...>" >&2
  exit 64
fi

COMMAND=("$@")

BENCH_DIR=${BENCH_DIR:-/home/frappe/frappe-bench}
SITE_NAME=${FRAPPE_SITE:-site1.local}
SITE_DB_NAME=${SITE_DB_NAME:-${SITE_NAME//./_}}
DB_HOST=${DB_HOST:-mariadb}
DB_PORT=${DB_PORT:-3306}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
CUSTOM_APP_NAME=${CUSTOM_APP_NAME:-hrms}
CUSTOM_APP_BRANCH=${CUSTOM_APP_BRANCH:-main}
CUSTOM_APP_REPO=${CUSTOM_APP_REPO:-/workspace/repo}
INSTALL_ERPNEXT=${INSTALL_ERPNEXT:-1}
BUILD_ASSETS_ON_START=${BUILD_ASSETS_ON_START:-1}
WAIT_FOR_DB_TIMEOUT=${WAIT_FOR_DB_TIMEOUT:-300}
LOCK_DIR="${BENCH_DIR}/sites/.bootstrap-lock"
MARKER_FILE="${BENCH_DIR}/sites/.bootstrap-complete"

if [[ -z "${MARIADB_ROOT_PASSWORD}" ]]; then
  echo "[ensure_site] MARIADB_ROOT_PASSWORD is required." >&2
  exit 65
fi

wait_for_port() {
  local host=$1
  local port=$2
  local timeout=$3
  local waited=0

  echo "[ensure_site] Waiting for ${host}:${port} (timeout ${timeout}s)"
  while ! (echo > /dev/tcp/${host}/${port}) &>/dev/null; do
    sleep 2
    waited=$((waited + 2))
    if [[ ${waited} -ge ${timeout} ]]; then
      echo "[ensure_site] Timeout while waiting for ${host}:${port}" >&2
      exit 67
    fi
  done
}

bootstrap_site() {
  cd "${BENCH_DIR}"

  if [[ ! -d "sites/${SITE_NAME}" ]]; then
    echo "[ensure_site] Creating site ${SITE_NAME}"
    bench new-site "${SITE_NAME}" \
      --force \
      --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
      --admin-password "${ADMIN_PASSWORD}" \
      --db-name "${SITE_DB_NAME}"
  else
    echo "[ensure_site] Site ${SITE_NAME} already exists"
  fi

  if [[ "${INSTALL_ERPNEXT}" != "0" ]]; then
    if ! bench --site "${SITE_NAME}" list-apps | grep -qx "erpnext"; then
      echo "[ensure_site] Installing ERPNext"
      bench --site "${SITE_NAME}" install-app erpnext
    fi
  fi

  bench --site "${SITE_NAME}" enable-scheduler || true
  bench --site "${SITE_NAME}" set-config developer_mode 0 || true
  bench --site "${SITE_NAME}" clear-cache || true
  bench use "${SITE_NAME}" || true
}

sync_custom_app() {
  cd "${BENCH_DIR}"

  export BENCH_DIR
  export CUSTOM_APP_NAME
  export CUSTOM_APP_BRANCH
  export CUSTOM_APP_REPO

  if [[ ! -d "${CUSTOM_APP_REPO}" ]]; then
    echo "[ensure_site] CUSTOM_APP_REPO path ${CUSTOM_APP_REPO} not found" >&2
    exit 66
  fi

  git config --global --add safe.directory "${CUSTOM_APP_REPO}" >/dev/null 2>&1 || true

  bash /workspace/repo/deploy/bootstrap_custom_app.sh

  if ! bench --site "${SITE_NAME}" list-apps | grep -qx "${CUSTOM_APP_NAME}"; then
    echo "[ensure_site] Installing custom app ${CUSTOM_APP_NAME}"
    bench --site "${SITE_NAME}" install-app "${CUSTOM_APP_NAME}"
  else
    echo "[ensure_site] ${CUSTOM_APP_NAME} already installed"
    bench --site "${SITE_NAME}" migrate || true
  fi
}

maybe_build_assets() {
  if [[ "${BUILD_ASSETS_ON_START}" == "0" ]]; then
    return
  fi

  cd "${BENCH_DIR}"
  echo "[ensure_site] Building production assets"
  bench build --production
}

wait_for_port "${DB_HOST}" "${DB_PORT}" "${WAIT_FOR_DB_TIMEOUT}"

if [[ -f "${MARKER_FILE}" ]]; then
  echo "[ensure_site] Bootstrap already completed — skipping site creation"
else
  if mkdir "${LOCK_DIR}" 2>/dev/null; then
    trap 'rm -rf "${LOCK_DIR}"' EXIT
    bootstrap_site
    touch "${MARKER_FILE}"
  else
    echo "[ensure_site] Waiting for another process to finish bootstrap"
    while [[ -d "${LOCK_DIR}" ]]; do sleep 2; done
    while [[ ! -f "${MARKER_FILE}" ]]; do sleep 1; done
  fi
fi

sync_custom_app
maybe_build_assets

exec "${COMMAND[@]}"
