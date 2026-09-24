#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$ROOT/build/installer"
STAGE="$WORK/secure-app-installer"
DIST="$ROOT/dist"
OUTPUT="$DIST/secure-app-installer.zip"

command -v python3 >/dev/null 2>&1 || {
    echo "ERROR: python3 missing" >&2
    exit 1
}

rm -rf "$WORK"

mkdir -p \
    "$STAGE/installer" \
    "$STAGE/builder" \
    "$STAGE/runtime" \
    "$STAGE/host/templates" \
    "$STAGE/gateway" \
    "$DIST"

install -m 0755 \
    "$ROOT/installer/install.sh" \
    "$STAGE/install.sh"

install -m 0644 \
    "$ROOT/installer/versions.env" \
    "$STAGE/installer/versions.env"

install -m 0755 \
    "$ROOT/builder/build-shared-runtime.sh" \
    "$STAGE/builder/build-shared-runtime.sh"

install -m 0755 \
    "$ROOT/host/appctl" \
    "$STAGE/host/appctl"

install -m 0644 \
    "$ROOT/host/templates/tuning.cfg" \
    "$STAGE/host/templates/tuning.cfg"

install -m 0644 \
    "$ROOT/host/99-secure-app-appliance.conf" \
    "$STAGE/host/99-secure-app-appliance.conf"

install -m 0644 \
    "$ROOT/gateway/Caddyfile" \
    "$STAGE/gateway/Caddyfile"

install -m 0644 \
    "$ROOT/gateway/compose.yaml" \
    "$STAGE/gateway/compose.yaml"

for file in \
    versions.env \
    shared.Dockerfile \
    redis.Dockerfile \
    AppCaddyfile \
    php-fpm-www.conf \
    shared-entrypoint.sh \
    redis-entrypoint.sh \
    apply-tuning.sh
do
    cp "$ROOT/runtime/$file" "$STAGE/runtime/$file"
done

chmod 0755 \
    "$STAGE/runtime/shared-entrypoint.sh" \
    "$STAGE/runtime/redis-entrypoint.sh" \
    "$STAGE/runtime/apply-tuning.sh"

rm -f "$OUTPUT"

python3 - "$STAGE" "$OUTPUT" <<'PY'
import os
import sys
import zipfile

source = os.path.abspath(sys.argv[1])
output = os.path.abspath(sys.argv[2])

with zipfile.ZipFile(
    output,
    "w",
    compression=zipfile.ZIP_DEFLATED,
    allowZip64=True,
) as archive:
    for base, dirs, files in os.walk(source):
        dirs.sort()
        files.sort()

        for name in files:
            path = os.path.join(base, name)
            arcname = os.path.relpath(path, source)
            archive.write(path, arcname)
PY

echo "INSTALLER=$OUTPUT"
ls -lh "$OUTPUT"
sha256sum "$OUTPUT"
echo "INSTALLER_BUILD=PASS"
