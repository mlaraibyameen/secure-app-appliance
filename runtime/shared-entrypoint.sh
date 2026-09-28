#!/bin/sh
set -eu

APP_ROOT="${APP_ROOT:-/opt/app}"
CONFIG_ROOT="${APP_CONFIG_ROOT:-/run/app-config}"
MANIFEST="${APP_MANIFEST:-/run/app-manifest/manifest.env}"
UNLOCK_FIFO="/run/secure-app/sws-unlock"

cfg_get() {
    file="$1"
    key="$2"
    default="$3"

    value="$(
        awk -v key="$key" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }

            {
                line=$0
                sub(/^[[:space:]]*/, "", line)

                split(line, a, "=")
                k=a[1]
                gsub(/[[:space:]]/, "", k)

                if (k == key) {
                    sub(/^[^=]*=/, "", line)
                    sub(/^[[:space:]]*/, "", line)
                    sub(/[[:space:]]*$/, "", line)
                    print line
                    exit
                }
            }
        ' "$file"
    )"

    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$default"
    fi
}

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

SECURITY_MODE="TEST_PLAINTEXT"

if [ -r "$MANIFEST" ]; then
    SECURITY_MODE="$(
        cfg_get \
            "$MANIFEST" \
            SECURITY_MODE \
            TEST_PLAINTEXT
    )"
fi

case "$SECURITY_MODE" in
    TEST_PLAINTEXT)
        exec /usr/local/bin/secure-app-start
        ;;
    SWS_V1)
        mkdir -p /run/secure-app
        chmod 0700 /run/secure-app
        rm -f             "$UNLOCK_FIFO"             /run/secure-app/sws-active

        mkfifo -m 0600 "$UNLOCK_FIFO"

        echo "SWS_STATE=LOCKED"
        echo "SWS_UNLOCK_FIFO=$UNLOCK_FIFO"

        exec \
            /usr/local/bin/sws-keyhold \
            /usr/local/bin/secure-app-start \
            < "$UNLOCK_FIFO"
        ;;
    *)
        echo "ERROR: unsupported SECURITY_MODE: $SECURITY_MODE" >&2
        exit 1
        ;;
esac
