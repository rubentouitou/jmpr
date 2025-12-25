#!bin/bash

set -euo pipefail

SITE_NAME=${FRAPPE_SITE:-hrms.localhost}
MARIADB_HOST=${MARIADB_HOST:-mariadb}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-123}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_URL="redis://${REDIS_HOST}:6379"
PORT_TO_BIND=${PORT:-8000}
YARN_CACHE_DIR=${YARN_CACHE_DIR:-/workspace/.yarn-cache}
YARN_NETWORK_TIMEOUT=${YARN_NETWORK_TIMEOUT:-600000}

mkdir -p "${YARN_CACHE_DIR}/npm"
export YARN_CACHE_FOLDER="${YARN_CACHE_DIR}"
export npm_config_cache="${YARN_CACHE_DIR}/npm"
export YARN_NETWORK_TIMEOUT
export npm_config_fetch_timeout="${YARN_NETWORK_TIMEOUT}"
export npm_config_fetch_retries=${npm_config_fetch_retries:-5}

yarn config set network-timeout "${YARN_NETWORK_TIMEOUT}" >/dev/null 2>&1 || true

PLACEHOLDER_PID=""

start_placeholder_server() {
    python3 -m http.server "${PORT_TO_BIND}" >/tmp/frappe_startup.log 2>&1 &
    PLACEHOLDER_PID=$!
    echo "Started placeholder server on port ${PORT_TO_BIND} (pid ${PLACEHOLDER_PID})"
}

stop_placeholder_server() {
    if [ -n "${PLACEHOLDER_PID}" ] && kill -0 "${PLACEHOLDER_PID}" 2>/dev/null; then
        kill "${PLACEHOLDER_PID}" 2>/dev/null || true
        wait "${PLACEHOLDER_PID}" 2>/dev/null || true
        echo "Stopped placeholder server"
    fi
}

start_placeholder_server
trap stop_placeholder_server EXIT

if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
    echo "Bench already exists, skipping init"
    cd frappe-bench
else
    echo "Creating new bench..."

    bench init --skip-redis-config-generation frappe-bench

    cd frappe-bench

    # Configure external services
    bench set-mariadb-host "${MARIADB_HOST}"
    bench set-redis-cache-host "${REDIS_URL}"
    bench set-redis-queue-host "${REDIS_URL}"
    bench set-redis-socketio-host "${REDIS_URL}"

    # Remove redis, watch from Procfile (handled externally)
    sed -i '/redis/d' ./Procfile
    sed -i '/watch/d' ./Procfile

    bench get-app erpnext
    bench get-app hrms

    if ! bench site list | grep -qx "${SITE_NAME}"; then
        bench new-site "${SITE_NAME}" \
            --force \
            --mariadb-root-password "${MARIADB_ROOT_PASSWORD}" \
            --admin-password "${ADMIN_PASSWORD}" \
            --no-mariadb-socket
    fi

    bench --site "${SITE_NAME}" install-app hrms
    bench --site "${SITE_NAME}" set-config developer_mode 1
    bench --site "${SITE_NAME}" enable-scheduler
    bench --site "${SITE_NAME}" clear-cache
    bench use "${SITE_NAME}"
fi

export PATH="${NVM_DIR}/versions/node/v${NODE_VERSION_DEVELOP}/bin/:${PATH}"

echo "Building assets before starting bench"
bench build --production

stop_placeholder_server
trap - EXIT

echo "Starting bench for site ${SITE_NAME} on port ${PORT_TO_BIND}"
exec bench --site "${SITE_NAME}" serve --port "${PORT_TO_BIND}" --host 0.0.0.0 --noreload