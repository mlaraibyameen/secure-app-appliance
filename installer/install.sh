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
    openssl \
    openssh-server \
    sudo \
    nano

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

if [ -f /etc/apt/sources.list.d/docker.sources ]; then
    rm -f /etc/apt/sources.list.d/docker.list
elif [ ! -f /etc/apt/sources.list.d/docker.list ]; then
    printf '%s\n' \
        "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
        > /etc/apt/sources.list.d/docker.list
fi

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
    "$BASE/keys/product_unlock_ed25519.pub" \
    /etc/secure-app-appliance/product_unlock_ed25519.pub

PRODUCT_KEY_FINGERPRINT="$(
    ssh-keygen \
        -lf /etc/secure-app-appliance/product_unlock_ed25519.pub \
        -E sha256 |
    awk '{print $2}'
)"

OPERATOR_USER="${SECURE_APP_OPERATOR_USER:-${SUDO_USER:-}}"

if [ -z "$OPERATOR_USER" ] || [ "$OPERATOR_USER" = "root" ]; then
    printf 'Operator username: ' >/dev/tty
    IFS= read -r OPERATOR_USER </dev/tty
fi

id "$OPERATOR_USER" >/dev/null 2>&1 || \
    die "operator user does not exist: $OPERATOR_USER"

OPERATOR_HOME="$(
    getent passwd "$OPERATOR_USER" |
    cut -d: -f6
)"

OPERATOR_GROUP="$(id -gn "$OPERATOR_USER")"

[ -n "$OPERATOR_HOME" ] || \
    die "unable to determine operator home"

install -d \
    -m 0700 \
    -o "$OPERATOR_USER" \
    -g "$OPERATOR_GROUP" \
    "$OPERATOR_HOME/.ssh"

touch "$OPERATOR_HOME/.ssh/authorized_keys"

chown \
    "$OPERATOR_USER:$OPERATOR_GROUP" \
    "$OPERATOR_HOME/.ssh/authorized_keys"

chmod 0600 \
    "$OPERATOR_HOME/.ssh/authorized_keys"

PRODUCT_KEY_BLOB="$(
    awk '{print $2}' \
        /etc/secure-app-appliance/product_unlock_ed25519.pub
)"

if ! grep -qF \
    "$PRODUCT_KEY_BLOB" \
    "$OPERATOR_HOME/.ssh/authorized_keys"
then
    cat \
        /etc/secure-app-appliance/product_unlock_ed25519.pub \
        >> "$OPERATOR_HOME/.ssh/authorized_keys"
fi

cat > /etc/secure-app-appliance/operator.env <<EOF_OPERATOR
OPERATOR_USER=$OPERATOR_USER
PRODUCT_KEY_FINGERPRINT=$PRODUCT_KEY_FINGERPRINT
EOF_OPERATOR

awk '
    {
        print "secure-app-product " $1 " " $2
    }
' /etc/secure-app-appliance/product_unlock_ed25519.pub \
    > /etc/secure-app-appliance/allowed_signers

chmod 0644 \
    /etc/secure-app-appliance/product_unlock_ed25519.pub \
    /etc/secure-app-appliance/operator.env \
    /etc/secure-app-appliance/allowed_signers

install -d -m 0755 \
    /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-secure-app-appliance.conf <<'EOF_SSHD'
ExposeAuthInfo yes
AllowAgentForwarding yes
PubkeyAuthentication yes
EOF_SSHD

/usr/sbin/sshd -t

cat > /etc/sudoers.d/secure-app-appliance <<EOF_SUDOERS
Defaults:$OPERATOR_USER env_keep += "SSH_USER_AUTH SSH_AUTH_SOCK SSH_CONNECTION"
$OPERATOR_USER ALL=(root) NOPASSWD: /usr/local/bin/appctl
$OPERATOR_USER ALL=(root) NOPASSWD: /usr/local/bin/appctl *
EOF_SUDOERS

chmod 0440 \
    /etc/sudoers.d/secure-app-appliance

visudo -cf \
    /etc/sudoers.d/secure-app-appliance \
    >/dev/null

systemctl enable --now ssh
systemctl reload ssh

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

./builder/build-shared-runtime.sh "$DEFAULT_RUNTIME_PROFILE"

set -a
. installer/versions.env
. runtime/versions.env
set +a

cat > /etc/secure-app-appliance/runtime.env <<EOF_RUNTIME
DEFAULT_RUNTIME_PROFILE=$DEFAULT_RUNTIME_PROFILE
RUNTIME_IMAGE_PREFIX=secure-app-runtime
RUNTIME_VERSION=$SECURE_RUNTIME_VERSION
RUNTIME_IMAGE=secure-app-runtime:$DEFAULT_RUNTIME_PROFILE-$SECURE_RUNTIME_VERSION
REDIS_IMAGE=secure-app-redis:$SECURE_RUNTIME_VERSION
GATEWAY_IMAGE=public.ecr.aws/docker/library/caddy:$CADDY_VERSION
EOF_RUNTIME

docker network inspect secure-app-gateway >/dev/null 2>&1 ||
    docker network create secure-app-gateway >/dev/null

: > /srv/secure-apps/_gateway/apps/_empty.caddy

docker compose \
    --project-name secure-app-gateway \
    --file /srv/secure-apps/_gateway/compose.yaml \
    up -d

sleep 2

install -d -m 0700 /run/secure-app-appliance
: > /run/secure-app-appliance/installing

if ! appctl doctor; then
    rm -f /run/secure-app-appliance/installing
    exit 1
fi

rm -f /run/secure-app-appliance/installing

echo "PRODUCT_KEY_FINGERPRINT=$PRODUCT_KEY_FINGERPRINT"
echo "OPERATOR_USER=$OPERATOR_USER"
echo "INSTALL=PASS"
echo "ROOT=/srv/secure-apps"
