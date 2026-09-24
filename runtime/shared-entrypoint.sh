#!/bin/sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/app}"
CONFIG_ROOT="${APP_CONFIG_ROOT:-/run/app-config}"

echo "=== SECURE APP RUNTIME STARTUP ==="

for required in \
    "$APP_ROOT/artisan" \
    "$APP_ROOT/public/index.php" \
    "$APP_ROOT/.env" \
    "$CONFIG_ROOT/tuning.cfg"
do
    if [ ! -r "$required" ]; then
        echo "ERROR: required file is missing or unreadable: $required" >&2
        exit 1
    fi
done

/usr/local/bin/apply-tuning

mkdir -p \
    "$APP_ROOT/storage/app/public" \
    "$APP_ROOT/storage/framework/cache/data" \
    "$APP_ROOT/storage/framework/sessions" \
    "$APP_ROOT/storage/framework/views" \
    "$APP_ROOT/storage/logs" \
    "$APP_ROOT/bootstrap/cache"

chown -R app:app \
    "$APP_ROOT/storage" \
    "$APP_ROOT/bootstrap/cache"

php-fpm -t
echo "PHP_FPM_CONFIG=VALID"

php-fpm -D
echo "PHP_FPM=STARTED"

exec caddy run \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile
