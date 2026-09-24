#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run this script as your normal WSL user, not as root."
  exit 1
fi

if [[ ! -f /etc/os-release ]]; then
  echo "Unable to identify Linux distribution."
  exit 1
fi

. /etc/os-release

if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  echo "This bootstrap currently supports Ubuntu 24.04 only."
  echo "Detected: ${PRETTY_NAME:-unknown}"
  exit 1
fi

if [[ "$(ps -p 1 -o comm=)" != "systemd" ]]; then
  echo "systemd is not active in this WSL instance."
  echo "Enable systemd before continuing."
  exit 1
fi

echo "==> Installing base tools"

sudo apt-get update

sudo apt-get install -y \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  openssh-client \
  age \
  zstd

echo "==> Configuring Docker repository"

sudo install -m 0755 -d /etc/apt/keyrings

if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

cat <<DOCKER_REPO | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_REPO

sudo apt-get update

echo "==> Installing Docker"

sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

sudo systemctl enable --now docker

if ! getent group docker >/dev/null; then
  sudo groupadd docker
fi

if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  DOCKER_GROUP_CHANGED=1
else
  DOCKER_GROUP_CHANGED=0
fi

echo
echo "==> Versions"

git --version
docker --version
docker buildx version
docker compose version
age --version
jq --version
zstd --version | head -n1
ssh -V 2>&1

echo
if [[ "$DOCKER_GROUP_CHANGED" -eq 1 ]]; then
  echo "BUILDER_SETUP=COMPLETE"
  echo "Docker group membership was added."
  echo "Restart the WSL session before using Docker without sudo."
else
  docker info >/dev/null
  echo "BUILDER_READY=YES"
fi
