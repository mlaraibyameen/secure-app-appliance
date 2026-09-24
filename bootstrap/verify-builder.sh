#!/usr/bin/env bash
set -uo pipefail

FAIL=0

pass() {
  printf '%-32s PASS\n' "$1"
}

fail() {
  printf '%-32s FAIL\n' "$1"
  FAIL=1
}

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$2"
  else
    fail "$2"
  fi
}

echo "=== SECURE APP BUILDER VERIFICATION ==="
echo

if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
    pass "Ubuntu 24.04"
  else
    fail "Ubuntu 24.04"
  fi
else
  fail "Ubuntu identification"
fi

if grep -qi microsoft /proc/version 2>/dev/null; then
  pass "WSL2 environment"
else
  fail "WSL2 environment"
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  pass "Architecture x86_64"
else
  fail "Architecture x86_64"
fi

if [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]]; then
  pass "systemd"
else
  fail "systemd"
fi

check_cmd git "Git"
check_cmd docker "Docker CLI"
check_cmd ssh "OpenSSH client"
check_cmd ssh-keygen "ssh-keygen"
check_cmd age "age"
check_cmd jq "jq"
check_cmd zstd "zstd"
check_cmd curl "curl"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    pass "Docker daemon"
  else
    fail "Docker daemon"
  fi

  if docker buildx version >/dev/null 2>&1; then
    pass "Docker Buildx"
  else
    fail "Docker Buildx"
  fi

  if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose"
  else
    fail "Docker Compose"
  fi
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -s "$REPO_ROOT/keys/product_unlock_ed25519" ]]; then
  pass "Product private key"
else
  fail "Product private key"
fi

if [[ -s "$REPO_ROOT/keys/product_unlock_ed25519.pub" ]]; then
  pass "Product public key"
else
  fail "Product public key"
fi

if [[ -s "$REPO_ROOT/keys/product_unlock_ed25519" && \
      -s "$REPO_ROOT/keys/product_unlock_ed25519.pub" ]]; then

  TMP_PUB="$(mktemp)"
  trap 'rm -f "$TMP_PUB"' EXIT

  chmod 600 "$REPO_ROOT/keys/product_unlock_ed25519"

  if ssh-keygen -y \
      -f "$REPO_ROOT/keys/product_unlock_ed25519" \
      > "$TMP_PUB" 2>/dev/null && \
     diff -q \
      <(awk '{print $1" "$2}' "$TMP_PUB") \
      <(awk '{print $1" "$2}' "$REPO_ROOT/keys/product_unlock_ed25519.pub") \
      >/dev/null 2>&1; then
    pass "Product keypair match"
  else
    fail "Product keypair match"
  fi
fi

echo

if [[ "$FAIL" -eq 0 ]]; then
  echo "BUILDER_READY=YES"
  exit 0
else
  echo "BUILDER_READY=NO"
  exit 1
fi
