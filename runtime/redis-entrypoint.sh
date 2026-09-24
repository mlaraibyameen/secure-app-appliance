#!/bin/sh
set -eu

CFG="${TUNING_CONFIG:-/run/app-config/tuning.cfg}"
REDIS_CONF="/tmp/redis-runtime.conf"

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
    case "$2" in
        ''|*[!0-9]*)
            echo "ERROR: $1 must be an integer, got: $2" >&2
            exit 1
            ;;
    esac
}

require_redis_size() {
    echo "$2" | grep -Eq '^[0-9]+([kKmMgG][bB]?)?$' || {
        echo "ERROR: $1 has invalid size: $2" >&2
        exit 1
    }
}

MAXMEMORY="$(cfg_get REDIS_MAXMEMORY 512mb)"
POLICY="$(cfg_get REDIS_MAXMEMORY_POLICY noeviction)"
DATABASES="$(cfg_get REDIS_DATABASES 16)"
BACKLOG="$(cfg_get REDIS_TCP_BACKLOG 511)"
TIMEOUT="$(cfg_get REDIS_TIMEOUT 0)"
KEEPALIVE="$(cfg_get REDIS_TCP_KEEPALIVE 300)"
APPENDONLY="$(cfg_get REDIS_APPENDONLY yes)"
APPENDFSYNC="$(cfg_get REDIS_APPENDFSYNC everysec)"

require_redis_size REDIS_MAXMEMORY "$MAXMEMORY"
require_int REDIS_DATABASES "$DATABASES"
require_int REDIS_TCP_BACKLOG "$BACKLOG"
require_int REDIS_TIMEOUT "$TIMEOUT"
require_int REDIS_TCP_KEEPALIVE "$KEEPALIVE"

case "$POLICY" in
    noeviction|allkeys-lru|allkeys-lfu|allkeys-random|volatile-lru|volatile-lfu|volatile-random|volatile-ttl)
        ;;
    *)
        echo "ERROR: invalid REDIS_MAXMEMORY_POLICY: $POLICY" >&2
        exit 1
        ;;
esac

case "$APPENDONLY" in
    yes|no) ;;
    *)
        echo "ERROR: REDIS_APPENDONLY must be yes or no" >&2
        exit 1
        ;;
esac

case "$APPENDFSYNC" in
    always|everysec|no) ;;
    *)
        echo "ERROR: invalid REDIS_APPENDFSYNC: $APPENDFSYNC" >&2
        exit 1
        ;;
esac

cat > "$REDIS_CONF" <<EOF_REDIS
bind 0.0.0.0
port 6379

# Redis is reachable only on the private appliance Docker network.
protected-mode no

dir /data
dbfilename dump.rdb

databases ${DATABASES}

tcp-backlog ${BACKLOG}
timeout ${TIMEOUT}
tcp-keepalive ${KEEPALIVE}

maxmemory ${MAXMEMORY}
maxmemory-policy ${POLICY}

appendonly ${APPENDONLY}
appendfilename "appendonly.aof"
appendfsync ${APPENDFSYNC}

save 900 1
save 300 10
save 60 10000

daemonize no
logfile ""
EOF_REDIS

echo "=== REDIS RUNTIME TUNING ==="
echo "REDIS_MAXMEMORY=$MAXMEMORY"
echo "REDIS_MAXMEMORY_POLICY=$POLICY"
echo "REDIS_DATABASES=$DATABASES"
echo "REDIS_APPENDONLY=$APPENDONLY"
echo "REDIS_APPENDFSYNC=$APPENDFSYNC"
echo "REDIS_TUNING=APPLIED"

exec redis-server "$REDIS_CONF"
