#!bin/bash

set -euo pipefail

SITE_NAME=${FRAPPE_SITE:-hrms.localhost}
MARIADB_HOST=${MARIADB_HOST:-mariadb}
MARIADB_ROOT_PASSWORD=${MARIADB_ROOT_PASSWORD:-123}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_URL="redis://${REDIS_HOST}:6379"
PORT_TO_BIND=${PORT:-8000}

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

echo "Starting bench for site ${SITE_NAME} on port ${PORT_TO_BIND}"
exec bench --site "${SITE_NAME}" serve --port "${PORT_TO_BIND}" --noreload