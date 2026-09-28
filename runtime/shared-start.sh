#!/bin/sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/app}"
CONFIG_ROOT="${APP_CONFIG_ROOT:-/run/app-config}"
LOADER_INI="/usr/local/etc/php/conf.d/zz-sws-loader.ini"

if [ -n "${SWS_KEY_FD:-}" ]; then
    printf '%s\n' \
        'extension=sws_loader.so' \
        > "$LOADER_INI"

    mkdir -p /run/secure-app

    php -r '
        $source = file_get_contents("/opt/app/public/index.php");

        if (
            !is_string($source) ||
            substr($source, 0, 5) !== "<?php"
        ) {
            exit(1);
        }
    '

    echo "SWS_LOADER=VALID"
else
    rm -f "$LOADER_INI"
    rm -f /run/secure-app/sws-active
fi

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

if [ -n "${SWS_KEY_FD:-}" ]; then
    : > /run/secure-app/sws-active
    chmod 0600 /run/secure-app/sws-active

    echo "SWS_ACTIVE=READY"

    exec 3<&-
    unset SWS_KEY_FD
fi

exec caddy run \
    --config /etc/caddy/Caddyfile \
    --adapter caddyfile
