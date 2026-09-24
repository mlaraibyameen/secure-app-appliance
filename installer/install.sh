#!/bin/sh
set -eu

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || die "run install.sh as root"

BASE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

[ -r "$BASE/installer/versions.env" ] || die "installer versions missing"

set -a
. "$BASE/installer/versions.env"
set +a

[ -r /etc/os-release ] || die "/etc/os-release missing"

. /etc/os-release

[ "$ID" = "ubuntu" ] || die "Ubuntu is required"

ARCH="$(dpkg --print-architecture)"

[ "$ARCH" = "amd64" ] || die "amd64 is currently required"

command -v apt-get >/dev/null 2>&1 || die "apt-get missing"
command -v systemctl >/dev/null 2>&1 || die "systemd missing"
command -v curl >/dev/null 2>&1 || true

echo "INSTALLER_VERSION=$INSTALLER_VERSION"
echo "UBUNTU_VERSION=$VERSION_ID"
echo "UBUNTU_CODENAME=$VERSION_CODENAME"
echo "ARCH=$ARCH"

apt-get update

apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    openssl

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

printf '%s\n' \
    "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update

apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

systemctl enable --now docker

docker info >/dev/null 2>&1 || die "Docker daemon unavailable"

echo "DOCKER=$(docker version --format '{{.Server.Version}}')"
echo "COMPOSE=$(docker compose version --short)"

mkdir -p \
    /etc/secure-app-appliance \
    /usr/share/secure-app-appliance \
    /usr/share/secure-app-appliance/runtime \
    /usr/share/secure-app-appliance/builder \
    /srv/secure-apps/_gateway/apps \
    /srv/secure-apps/_gateway/tls \
    /srv/secure-apps/_gateway/data \
    /srv/secure-apps/_gateway/config

cp -a "$BASE/runtime/." \
    /usr/share/secure-app-appliance/runtime/

install -m 0755 \
    "$BASE/builder/build-shared-runtime.sh" \
    /usr/share/secure-app-appliance/builder/build-shared-runtime.sh

install -m 0644 \
    "$BASE/installer/versions.env" \
    /usr/share/secure-app-appliance/installer-versions.env

install -m 0644 \
    "$BASE/installer/versions.env" \
    /etc/secure-app-appliance/versions.env

install -m 0755 \
    "$BASE/host/appctl" \
    /usr/local/bin/appctl

install -m 0644 \
    "$BASE/host/templates/tuning.cfg" \
    /usr/share/secure-app-appliance/tuning.cfg

install -m 0644 \
    "$BASE/host/99-secure-app-appliance.conf" \
    /etc/sysctl.d/99-secure-app-appliance.conf

install -m 0644 \
    "$BASE/gateway/Caddyfile" \
    /srv/secure-apps/_gateway/Caddyfile

install -m 0644 \
    "$BASE/gateway/compose.yaml" \
    /srv/secure-apps/_gateway/compose.yaml

sysctl --system >/dev/null

cd /usr/share/secure-app-appliance

mkdir -p installer

cp installer-versions.env installer/versions.env

./builder/build-shared-runtime.sh

set -a
. installer/versions.env
. runtime/versions.env
set +a

cat > /etc/secure-app-appliance/runtime.env <<EOF_RUNTIME
RUNTIME_IMAGE=secure-app-runtime:$SECURE_RUNTIME_VERSION
REDIS_IMAGE=secure-app-redis:$SECURE_RUNTIME_VERSION
GATEWAY_IMAGE=caddy:$CADDY_VERSION
EOF_RUNTIME

docker network inspect secure-app-gateway >/dev/null 2>&1 ||
    docker network create secure-app-gateway >/dev/null

: > /srv/secure-apps/_gateway/apps/_empty.caddy

docker compose \
    --project-name secure-app-gateway \
    --file /srv/secure-apps/_gateway/compose.yaml \
    up -d

sleep 2

appctl doctor

echo "INSTALL=PASS"
echo "ROOT=/srv/secure-apps"
