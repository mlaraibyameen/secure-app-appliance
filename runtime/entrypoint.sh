#!/bin/sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/app}"
CONFIG_ROOT="${APP_CONFIG_ROOT:-/run/app-config}"

echo "=== SECURE APP STARTUP ==="

# ------------------------------------------------------------
# External application configuration
# ------------------------------------------------------------

if [ ! -r "$CONFIG_ROOT/.env" ]; then
    echo "ERROR: $CONFIG_ROOT/.env is missing or unreadable" >&2
    exit 1
fi

if [ ! -r "$CONFIG_ROOT/tuning.cfg" ]; then
    echo "ERROR: $CONFIG_ROOT/tuning.cfg is missing or unreadable" >&2
    exit 1
fi

rm -f "$APP_ROOT/.env"
ln -s "$CONFIG_ROOT/.env" "$APP_ROOT/.env"

echo "ENV_CONFIG=READY"
echo "TUNING_CONFIG=READY"

# ------------------------------------------------------------
# Generate runtime configuration on every container start
# ------------------------------------------------------------

/usr/local/bin/apply-tuning

# ------------------------------------------------------------
# Laravel writable paths
# ------------------------------------------------------------

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

# ------------------------------------------------------------
# Validate generated PHP/FPM configuration
# ------------------------------------------------------------

php-fpm -t

echo "PHP_FPM_CONFIG=VALID"

# ------------------------------------------------------------
# Start PHP-FPM and Caddy
# ------------------------------------------------------------

php-fpm -D

echo "PHP_FPM=STARTED"

exec caddy run \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile
