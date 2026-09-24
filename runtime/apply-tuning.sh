#!/bin/sh
set -eu

CFG="${TUNING_CONFIG:-/run/app-config/tuning.cfg}"

[ -r "$CFG" ] || {
    echo "ERROR: tuning config not readable: $CFG" >&2
    exit 1
}

cfg_get() {
    key="$1"
    default="$2"

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
        ' "$CFG"
    )"

    if [ -n "$value" ]; then
        printf '%s' "$value"
    else
        printf '%s' "$default"
    fi
}

require_int() {
    name="$1"
    value="$2"

    case "$value" in
        ''|*[!0-9]*)
            echo "ERROR: $name must be an integer, got: $value" >&2
            exit 1
            ;;
    esac
}

require_bool() {
    name="$1"
    value="$2"

    case "$value" in
        0|1) ;;
        *)
            echo "ERROR: $name must be 0 or 1, got: $value" >&2
            exit 1
            ;;
    esac
}

require_size() {
    name="$1"
    value="$2"

    echo "$value" | grep -Eq '^[0-9]+([KMG])?$' || {
        echo "ERROR: $name has invalid size: $value" >&2
        exit 1
    }
}

require_duration() {
    name="$1"
    value="$2"

    echo "$value" | grep -Eq '^[0-9]+(ms|s|m|h)?$' || {
        echo "ERROR: $name has invalid duration: $value" >&2
        exit 1
    }
}

# ------------------------------------------------------------
# PHP-FPM
# ------------------------------------------------------------

FPM_PM="$(cfg_get PHP_FPM_PM dynamic)"
FPM_MAX_CHILDREN="$(cfg_get PHP_FPM_MAX_CHILDREN 10)"
FPM_START_SERVERS="$(cfg_get PHP_FPM_START_SERVERS 2)"
FPM_MIN_SPARE="$(cfg_get PHP_FPM_MIN_SPARE_SERVERS 1)"
FPM_MAX_SPARE="$(cfg_get PHP_FPM_MAX_SPARE_SERVERS 4)"
FPM_MAX_REQUESTS="$(cfg_get PHP_FPM_MAX_REQUESTS 500)"
FPM_TERMINATE="$(cfg_get PHP_FPM_REQUEST_TERMINATE_TIMEOUT 120s)"
FPM_SLOWLOG_TIMEOUT="$(cfg_get PHP_FPM_REQUEST_SLOWLOG_TIMEOUT 5s)"

case "$FPM_PM" in
    dynamic|static|ondemand) ;;
    *)
        echo "ERROR: invalid PHP_FPM_PM: $FPM_PM" >&2
        exit 1
        ;;
esac

require_int PHP_FPM_MAX_CHILDREN "$FPM_MAX_CHILDREN"
require_int PHP_FPM_START_SERVERS "$FPM_START_SERVERS"
require_int PHP_FPM_MIN_SPARE_SERVERS "$FPM_MIN_SPARE"
require_int PHP_FPM_MAX_SPARE_SERVERS "$FPM_MAX_SPARE"
require_int PHP_FPM_MAX_REQUESTS "$FPM_MAX_REQUESTS"
require_duration PHP_FPM_REQUEST_TERMINATE_TIMEOUT "$FPM_TERMINATE"
require_duration PHP_FPM_REQUEST_SLOWLOG_TIMEOUT "$FPM_SLOWLOG_TIMEOUT"

{
    echo '[www]'
    echo "pm = $FPM_PM"
    echo "pm.max_children = $FPM_MAX_CHILDREN"
    echo "pm.max_requests = $FPM_MAX_REQUESTS"
    echo "request_terminate_timeout = $FPM_TERMINATE"
    echo "request_slowlog_timeout = $FPM_SLOWLOG_TIMEOUT"
    echo 'slowlog = /proc/self/fd/2'

    case "$FPM_PM" in
        dynamic)
            echo "pm.start_servers = $FPM_START_SERVERS"
            echo "pm.min_spare_servers = $FPM_MIN_SPARE"
            echo "pm.max_spare_servers = $FPM_MAX_SPARE"
            ;;
        ondemand)
            echo 'pm.process_idle_timeout = 10s'
            ;;
    esac
} > /usr/local/etc/php-fpm.d/zz-runtime-tuning.conf

# ------------------------------------------------------------
# PHP / OPcache / APCu
# ------------------------------------------------------------

PHP_MEMORY_LIMIT="$(cfg_get PHP_MEMORY_LIMIT 512M)"
PHP_MAX_EXECUTION_TIME="$(cfg_get PHP_MAX_EXECUTION_TIME 120)"
PHP_MAX_INPUT_TIME="$(cfg_get PHP_MAX_INPUT_TIME 120)"
PHP_MAX_INPUT_VARS="$(cfg_get PHP_MAX_INPUT_VARS 5000)"
PHP_UPLOAD_MAX="$(cfg_get PHP_UPLOAD_MAX_FILESIZE 128M)"
PHP_POST_MAX="$(cfg_get PHP_POST_MAX_SIZE 128M)"
PHP_MAX_UPLOADS="$(cfg_get PHP_MAX_FILE_UPLOADS 20)"
REALPATH_SIZE="$(cfg_get PHP_REALPATH_CACHE_SIZE 16M)"
REALPATH_TTL="$(cfg_get PHP_REALPATH_CACHE_TTL 600)"
DISPLAY_ERRORS="$(cfg_get PHP_DISPLAY_ERRORS 0)"
LOG_ERRORS="$(cfg_get PHP_LOG_ERRORS 1)"
EXPOSE_PHP="$(cfg_get PHP_EXPOSE_PHP 0)"

OPCACHE_ENABLE="$(cfg_get OPCACHE_ENABLE 1)"
OPCACHE_ENABLE_CLI="$(cfg_get OPCACHE_ENABLE_CLI 0)"
OPCACHE_MEMORY="$(cfg_get OPCACHE_MEMORY_CONSUMPTION 256)"
OPCACHE_STRINGS="$(cfg_get OPCACHE_INTERNED_STRINGS_BUFFER 32)"
OPCACHE_FILES="$(cfg_get OPCACHE_MAX_ACCELERATED_FILES 20000)"
OPCACHE_WASTED="$(cfg_get OPCACHE_MAX_WASTED_PERCENTAGE 5)"
OPCACHE_VALIDATE="$(cfg_get OPCACHE_VALIDATE_TIMESTAMPS 0)"
OPCACHE_REVALIDATE="$(cfg_get OPCACHE_REVALIDATE_FREQ 0)"
OPCACHE_PROTECTION="$(cfg_get OPCACHE_FILE_UPDATE_PROTECTION 0)"
OPCACHE_COMMENTS="$(cfg_get OPCACHE_SAVE_COMMENTS 1)"
OPCACHE_JIT="$(cfg_get OPCACHE_JIT off)"
OPCACHE_JIT_BUFFER="$(cfg_get OPCACHE_JIT_BUFFER_SIZE 0)"

APCU_ENABLED="$(cfg_get APCU_ENABLED 1)"
APCU_ENABLE_CLI="$(cfg_get APCU_ENABLE_CLI 0)"
APCU_SIZE="$(cfg_get APCU_SHM_SIZE 64M)"
APCU_TTL="$(cfg_get APCU_TTL 0)"
APCU_GC_TTL="$(cfg_get APCU_GC_TTL 3600)"

require_size PHP_MEMORY_LIMIT "$PHP_MEMORY_LIMIT"
require_int PHP_MAX_EXECUTION_TIME "$PHP_MAX_EXECUTION_TIME"
require_int PHP_MAX_INPUT_TIME "$PHP_MAX_INPUT_TIME"
require_int PHP_MAX_INPUT_VARS "$PHP_MAX_INPUT_VARS"
require_size PHP_UPLOAD_MAX_FILESIZE "$PHP_UPLOAD_MAX"
require_size PHP_POST_MAX_SIZE "$PHP_POST_MAX"
require_int PHP_MAX_FILE_UPLOADS "$PHP_MAX_UPLOADS"
require_size PHP_REALPATH_CACHE_SIZE "$REALPATH_SIZE"
require_int PHP_REALPATH_CACHE_TTL "$REALPATH_TTL"

require_bool PHP_DISPLAY_ERRORS "$DISPLAY_ERRORS"
require_bool PHP_LOG_ERRORS "$LOG_ERRORS"
require_bool PHP_EXPOSE_PHP "$EXPOSE_PHP"

require_bool OPCACHE_ENABLE "$OPCACHE_ENABLE"
require_bool OPCACHE_ENABLE_CLI "$OPCACHE_ENABLE_CLI"
require_int OPCACHE_MEMORY_CONSUMPTION "$OPCACHE_MEMORY"
require_int OPCACHE_INTERNED_STRINGS_BUFFER "$OPCACHE_STRINGS"
require_int OPCACHE_MAX_ACCELERATED_FILES "$OPCACHE_FILES"
require_int OPCACHE_MAX_WASTED_PERCENTAGE "$OPCACHE_WASTED"
require_bool OPCACHE_VALIDATE_TIMESTAMPS "$OPCACHE_VALIDATE"
require_int OPCACHE_REVALIDATE_FREQ "$OPCACHE_REVALIDATE"
require_int OPCACHE_FILE_UPDATE_PROTECTION "$OPCACHE_PROTECTION"
require_bool OPCACHE_SAVE_COMMENTS "$OPCACHE_COMMENTS"

require_bool APCU_ENABLED "$APCU_ENABLED"
require_bool APCU_ENABLE_CLI "$APCU_ENABLE_CLI"
require_size APCU_SHM_SIZE "$APCU_SIZE"
require_int APCU_TTL "$APCU_TTL"
require_int APCU_GC_TTL "$APCU_GC_TTL"

case "$OPCACHE_JIT" in
    off|disable|function|tracing|0|1)
        ;;
    *)
        echo "ERROR: invalid OPCACHE_JIT: $OPCACHE_JIT" >&2
        exit 1
        ;;
esac

case "$OPCACHE_JIT_BUFFER" in
    0)
        ;;
    *)
        require_size OPCACHE_JIT_BUFFER_SIZE "$OPCACHE_JIT_BUFFER"
        ;;
esac

cat > /usr/local/etc/php/conf.d/99-runtime-tuning.ini <<EOF_PHP
; Generated from /run/app-config/tuning.cfg on container startup.

memory_limit=${PHP_MEMORY_LIMIT}
max_execution_time=${PHP_MAX_EXECUTION_TIME}
max_input_time=${PHP_MAX_INPUT_TIME}
max_input_vars=${PHP_MAX_INPUT_VARS}

upload_max_filesize=${PHP_UPLOAD_MAX}
post_max_size=${PHP_POST_MAX}
max_file_uploads=${PHP_MAX_UPLOADS}

realpath_cache_size=${REALPATH_SIZE}
realpath_cache_ttl=${REALPATH_TTL}

display_errors=${DISPLAY_ERRORS}
display_startup_errors=0
log_errors=${LOG_ERRORS}
expose_php=${EXPOSE_PHP}

opcache.enable=${OPCACHE_ENABLE}
opcache.enable_cli=${OPCACHE_ENABLE_CLI}
opcache.memory_consumption=${OPCACHE_MEMORY}
opcache.interned_strings_buffer=${OPCACHE_STRINGS}
opcache.max_accelerated_files=${OPCACHE_FILES}
opcache.max_wasted_percentage=${OPCACHE_WASTED}
opcache.validate_timestamps=${OPCACHE_VALIDATE}
opcache.revalidate_freq=${OPCACHE_REVALIDATE}
opcache.file_update_protection=${OPCACHE_PROTECTION}
opcache.save_comments=${OPCACHE_COMMENTS}
opcache.jit=${OPCACHE_JIT}
opcache.jit_buffer_size=${OPCACHE_JIT_BUFFER}

apc.enabled=${APCU_ENABLED}
apc.enable_cli=${APCU_ENABLE_CLI}
apc.shm_size=${APCU_SIZE}
apc.ttl=${APCU_TTL}
apc.gc_ttl=${APCU_GC_TTL}
EOF_PHP

echo "TUNING_CONFIG=$CFG"
echo "PHP_FPM_PM=$FPM_PM"
echo "PHP_FPM_MAX_CHILDREN=$FPM_MAX_CHILDREN"
echo "PHP_MEMORY_LIMIT=$PHP_MEMORY_LIMIT"
echo "OPCACHE_MEMORY_CONSUMPTION=$OPCACHE_MEMORY"
echo "OPCACHE_MAX_ACCELERATED_FILES=$OPCACHE_FILES"
echo "APCU_SHM_SIZE=$APCU_SIZE"
echo "RUNTIME_TUNING=APPLIED"
