#!/usr/bin/env bash
set -euo pipefail

echo "=== SYSTEM ==="
uname -a
echo
cat /etc/os-release
echo

echo "=== WSL ==="
if grep -qi microsoft /proc/version; then
  echo "WSL=YES"
else
  echo "WSL=NO"
fi
echo

echo "=== CPU / MEMORY ==="
nproc
free -h
echo

echo "=== DISK ==="
df -h /
echo

echo "=== TOOLS ==="
for cmd in git docker php composer node npm gcc g++ make cmake rustc cargo age ssh ssh-keygen jq tar zstd; do
  printf "%-12s " "$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    case "$cmd" in
      docker) docker --version ;;
      php) php -v | head -n1 ;;
      composer) composer --version 2>/dev/null | head -n1 ;;
      node) node --version ;;
      npm) npm --version ;;
      git) git --version ;;
      gcc) gcc --version | head -n1 ;;
      g++) g++ --version | head -n1 ;;
      make) make --version | head -n1 ;;
      cmake) cmake --version | head -n1 ;;
      rustc) rustc --version ;;
      cargo) cargo --version ;;
      age) age --version ;;
      ssh) ssh -V 2>&1 ;;
      ssh-keygen) ssh-keygen -? 2>&1 | head -n1 || true ;;
      jq) jq --version ;;
      tar) tar --version | head -n1 ;;
      zstd) zstd --version | head -n1 ;;
    esac
  else
    echo "NOT INSTALLED"
  fi
done

echo
echo "=== DOCKER INFO ==="
if command -v docker >/dev/null 2>&1; then
  docker info --format 'ServerVersion={{.ServerVersion}} Driver={{.Driver}} CgroupVersion={{.CgroupVersion}}' 2>/dev/null || echo "Docker daemon not accessible"
  docker buildx version 2>/dev/null || echo "Buildx not available"
fi
