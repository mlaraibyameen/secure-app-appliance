#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

set -a
. "$ROOT/runtime/versions.env"
. "$ROOT/installer/versions.env"
set +a

RUNTIME_IMAGE="secure-app-runtime:$SECURE_RUNTIME_VERSION"
REDIS_IMAGE="secure-app-redis:$SECURE_RUNTIME_VERSION"
GATEWAY_IMAGE="caddy:$CADDY_VERSION"

echo "=== BUILD SHARED RUNTIME ==="
echo "RUNTIME_IMAGE=$RUNTIME_IMAGE"
echo "REDIS_IMAGE=$REDIS_IMAGE"
echo "GATEWAY_IMAGE=$GATEWAY_IMAGE"
echo

docker build \
    --build-arg PHP_VERSION="$PHP_VERSION" \
    --build-arg CADDY_VERSION="$CADDY_VERSION" \
    --build-arg OCI8_VERSION="$OCI8_VERSION" \
    --build-arg PHPREDIS_VERSION="$PHPREDIS_VERSION" \
    --build-arg APCU_VERSION="$APCU_VERSION" \
    --build-arg ORACLE_INSTANTCLIENT_SHORT="$ORACLE_INSTANTCLIENT_SHORT" \
    --build-arg ORACLE_BASIC_FILENAME="$ORACLE_BASIC_FILENAME" \
    --build-arg ORACLE_BASIC_SHA256="$ORACLE_BASIC_SHA256" \
    --build-arg ORACLE_SDK_FILENAME="$ORACLE_SDK_FILENAME" \
    --build-arg ORACLE_SDK_SHA256="$ORACLE_SDK_SHA256" \
    --build-arg APP_RUNTIME_USER="$APP_RUNTIME_USER" \
    --build-arg APP_RUNTIME_UID="$APP_RUNTIME_UID" \
    --build-arg APP_RUNTIME_GID="$APP_RUNTIME_GID" \
    --build-arg APP_HTTP_PORT="$APP_HTTP_PORT" \
    -t "$RUNTIME_IMAGE" \
    -f "$ROOT/runtime/shared.Dockerfile" \
    "$ROOT"

docker build \
    --build-arg REDIS_SERVER_VERSION="$REDIS_SERVER_VERSION" \
    -t "$REDIS_IMAGE" \
    -f "$ROOT/runtime/redis.Dockerfile" \
    "$ROOT"

docker pull "$GATEWAY_IMAGE"

echo
echo "=== VERIFY PHP RUNTIME ==="

docker run \
    --rm \
    --entrypoint php \
    "$RUNTIME_IMAGE" \
    -r '
$required = [
    "redis",
    "apcu",
    "Zend OPcache",
    "oci8",
    "pdo_mysql",
    "gd",
    "zip"
];

foreach ($required as $extension) {
    if (!extension_loaded($extension)) {
        fwrite(STDERR, "MISSING_EXTENSION=" . $extension . PHP_EOL);
        exit(1);
    }

    echo "EXTENSION=" . $extension . ":PASS" . PHP_EOL;
}

if (file_exists("/opt/app/artisan")) {
    fwrite(STDERR, "APP_SOURCE_PRESENT=YES" . PHP_EOL);
    exit(1);
}

echo "APP_SOURCE_PRESENT=NO" . PHP_EOL;
echo "PHP_RUNTIME=PASS" . PHP_EOL;
'

echo
echo "=== VERIFY REDIS ==="

docker run \
    --rm \
    --entrypoint redis-server \
    "$REDIS_IMAGE" \
    --version

echo
echo "RUNTIME_IMAGE=$RUNTIME_IMAGE"
echo "REDIS_IMAGE=$REDIS_IMAGE"
echo "GATEWAY_IMAGE=$GATEWAY_IMAGE"
echo "SHARED_RUNTIME_BUILD=PASS"
