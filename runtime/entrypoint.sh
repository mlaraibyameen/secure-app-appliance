#!/bin/sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/app}"

mkdir -p \
    "$APP_ROOT/storage/app/public" \
    "$APP_ROOT/storage/framework/cache/data" \
    "$APP_ROOT/storage/framework/sessions" \
    "$APP_ROOT/storage/framework/views" \
    "$APP_ROOT/storage/logs"

chown -R app:app "$APP_ROOT/storage"

php-fpm -D

exec caddy run \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile
