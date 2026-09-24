#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --app <path> --version <version>"
  exit 1
}

APP=""
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP="${2:-}"
      shift 2
      ;;
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$APP" && -n "$VERSION" ]] || usage

APP="$(realpath "$APP")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$APP/artisan" ]] || { echo "ERROR: artisan not found"; exit 1; }
[[ -f "$APP/composer.json" ]] || { echo "ERROR: composer.json not found"; exit 1; }
[[ -f "$APP/vendor/autoload.php" ]] || { echo "ERROR: vendor/autoload.php not found"; exit 1; }
[[ -f "$APP/public/index.php" ]] || { echo "ERROR: public/index.php not found"; exit 1; }

PRODUCT="new-admission-portal"

BUILD_ROOT="$REPO_ROOT/build/$PRODUCT/$VERSION"
APP_STAGE="$BUILD_ROOT/app"
DIST_ROOT="$REPO_ROOT/dist/$PRODUCT/$VERSION"

rm -rf "$BUILD_ROOT" "$DIST_ROOT"
mkdir -p "$APP_STAGE" "$DIST_ROOT"

echo "==> Staging $PRODUCT $VERSION"

rsync -a \
  --delete \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='.env.*' \
  --exclude='storage/***' \
  --exclude='node_modules/' \
  --exclude='*.sql' \
  --exclude='*.tar' \
  --exclude='*.tar.gz' \
  --exclude='*.tar.zst' \
  "$APP/" \
  "$APP_STAGE/"

mkdir -p "$APP_STAGE/storage"

rm -rf "$APP_STAGE/public/storage"
ln -s ../storage/app/public "$APP_STAGE/public/storage"

cat > "$BUILD_ROOT/release.env" <<META
PRODUCT=$PRODUCT
VERSION=$VERSION
META

echo
echo "=== RELEASE STAGING ==="
echo "PRODUCT=$PRODUCT"
echo "VERSION=$VERSION"
echo "SOURCE=$APP"
echo "STAGED_APP=$APP_STAGE"
echo "DIST=$DIST_ROOT"

echo
echo "=== SECURITY CHECK ==="

if find "$APP_STAGE" -maxdepth 1 -name '.env*' -print -quit | grep -q .; then
  echo "ENV_INCLUDED=YES"
  exit 1
else
  echo "ENV_INCLUDED=NO"
fi

if find "$APP_STAGE" -type f \( -name '*.sql' -o -name '*.tar.gz' -o -name '*.tar.zst' \) -print -quit | grep -q .; then
  echo "FORBIDDEN_ARCHIVE_OR_SQL=YES"
  exit 1
else
  echo "FORBIDDEN_ARCHIVE_OR_SQL=NO"
fi

if [[ -L "$APP_STAGE/public/storage" ]] && \
   [[ "$(readlink "$APP_STAGE/public/storage")" == "../storage/app/public" ]]; then
  echo "PUBLIC_STORAGE_LINK=PASS"
else
  echo "PUBLIC_STORAGE_LINK=FAIL"
  exit 1
fi

echo
echo "RELEASE_STAGE_READY=YES"
