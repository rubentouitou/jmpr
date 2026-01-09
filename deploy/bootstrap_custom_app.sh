#!/usr/bin/env bash
set -euo pipefail

BENCH_DIR=${BENCH_DIR:-/home/frappe/frappe-bench}
APP_NAME=${CUSTOM_APP_NAME:-hrms}
APP_BRANCH=${CUSTOM_APP_BRANCH:-main}
APP_SOURCE=${CUSTOM_APP_REPO:-/workspace}

cd "${BENCH_DIR}"

if [[ -z "${APP_SOURCE}" ]]; then
  echo "[bootstrap] CUSTOM_APP_REPO is empty; skipping custom app sync." >&2
  exit 0
fi

SOURCE_ARG="${APP_SOURCE}"
IS_REMOTE=0

if [[ "${APP_SOURCE}" =~ ^(https?://|git@|ssh://) ]]; then
  IS_REMOTE=1
fi

if [[ ${IS_REMOTE} -eq 0 && ! -d "${APP_SOURCE}" ]]; then
  echo "[bootstrap] Custom app path '${APP_SOURCE}' not found." >&2
  exit 1
fi

if [[ ${IS_REMOTE} -eq 0 && ! -d "${APP_SOURCE}/.git" ]]; then
  echo "[bootstrap] Path '${APP_SOURCE}' is not a git repository. Bench get-app requires a git repo." >&2
  exit 1
fi

if bench version >/dev/null 2>&1; then
  echo "[bootstrap] Syncing ${APP_NAME} (${APP_BRANCH}) from ${APP_SOURCE}" >&2
fi

bench get-app --branch "${APP_BRANCH}" --overwrite "${SOURCE_ARG}"

# Ensure python dependencies are present; ignore failures so the caller can continue.
bench setup requirements >/dev/null 2>&1 || true
