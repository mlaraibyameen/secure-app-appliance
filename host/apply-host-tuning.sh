#!/bin/sh
set -eu

SOURCE_FILE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/99-secure-app-appliance.conf"
TARGET_FILE="/etc/sysctl.d/99-secure-app-appliance.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run this script as root" >&2
    exit 1
fi

install -m 0644 "$SOURCE_FILE" "$TARGET_FILE"

sysctl --system >/dev/null

echo "=== SECURE APP HOST TUNING ==="
sysctl vm.overcommit_memory
sysctl net.core.rmem_max
sysctl net.core.wmem_max

echo "HOST_TUNING=APPLIED"
