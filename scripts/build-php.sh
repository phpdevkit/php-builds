#!/usr/bin/env bash
#
# build-php.sh
#
# Builds a static PHP CLI + FrankenPHP binary for a specific PHP version.
# Uses static-php-cli (spc) to compile both targets in a single build.
# Automatically fetches the latest FrankenPHP release for the source.
#
# Usage: ./build-php.sh <php_version> <os> <arch>
#
# Example: ./build-php.sh 8.4.3 linux x86_64
#
# Output: output/php-{php_version}-{os}-{arch}.tar.gz
#   Contains: bin/php (full CLI) and bin/frankenphp (web server)

set -euo pipefail

PHP_VERSION="${1:?Usage: build-php.sh <php_version> <os> <arch>}"
OS="${2:?Usage: build-php.sh <php_version> <os> <arch>}"
ARCH="${3:?Usage: build-php.sh <php_version> <os> <arch>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"
BUILD_DIR="${SCRIPT_DIR}/../build"
OUTPUT_DIR="${SCRIPT_DIR}/../output"
OUTPUT_NAME="php-${PHP_VERSION}-${OS}-${ARCH}"

# Auto-detect latest FrankenPHP release
echo "=== Detecting latest FrankenPHP release ==="
FRANKENPHP_VERSION=$(gh release view --repo dunglas/frankenphp --json tagName --jq '.tagName' 2>/dev/null || echo "")
if [[ -z "$FRANKENPHP_VERSION" ]]; then
    # Fallback: query the API directly
    FRANKENPHP_VERSION=$(curl -fsSL "https://api.github.com/repos/dunglas/frankenphp/releases/latest" | jq -r '.tag_name')
fi
echo "Using FrankenPHP ${FRANKENPHP_VERSION}"

echo "=== Building PHP ${PHP_VERSION} (CLI + FrankenPHP ${FRANKENPHP_VERSION}) for ${OS}-${ARCH} ==="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Clone FrankenPHP source at latest version (needed by spc --build-frankenphp)
FRANKENPHP_DIR="${BUILD_DIR}/frankenphp"
rm -rf "$FRANKENPHP_DIR"
echo "Cloning FrankenPHP ${FRANKENPHP_VERSION}..."
git clone --depth 1 --branch "${FRANKENPHP_VERSION}" \
    https://github.com/dunglas/frankenphp.git "$FRANKENPHP_DIR"
export FRANKENPHP_SOURCE_PATH="$FRANKENPHP_DIR"

# Download or update static-php-cli
SPC_DIR="${BUILD_DIR}/static-php-cli"
if [[ ! -d "$SPC_DIR" ]]; then
    echo "Cloning static-php-cli..."
    git clone --depth 1 https://github.com/crazywhalecc/static-php-cli "$SPC_DIR"
else
    echo "Updating static-php-cli..."
    cd "$SPC_DIR" && git pull && cd -
fi

cd "$SPC_DIR"

# Install spc dependencies
composer install --no-dev --no-interaction --quiet 2>/dev/null || true

# Map architecture names
case "$ARCH" in
    x86_64)  SPC_ARCH="x86_64" ;;
    aarch64) SPC_ARCH="aarch64" ;;
    *)       SPC_ARCH="$ARCH" ;;
esac

# Use the spc binary or PHP script
if [[ -f "bin/spc" ]]; then
    SPC="./bin/spc"
elif [[ -f "bin/spc-linux-${SPC_ARCH}" ]]; then
    SPC="./bin/spc-linux-${SPC_ARCH}"
else
    SPC="php bin/spc"
fi

# Set up build environment (installs pkg-config, etc.)
echo "=== Setting up build environment ==="
$SPC doctor --auto-fix

# Install xcaddy (needed for FrankenPHP build)
$SPC install-pkg go-xcaddy

# Extensions to build
EXTENSIONS=$(yq -r '.extensions // "all"' "$CONFIG_FILE")
if [[ "$EXTENSIONS" == "all" ]]; then
    # Common extensions for Laravel/Symfony development
    EXTENSIONS="bcmath,calendar,ctype,curl,dom,exif,fileinfo,filter,gd,iconv,intl,mbstring,mysqli,mysqlnd,opcache,openssl,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,posix,readline,redis,session,simplexml,soap,sockets,sodium,sqlite3,tokenizer,xml,xmlreader,xmlwriter,zip,zlib"
fi

echo "=== Downloading PHP ${PHP_VERSION} sources ==="
$SPC download --with-php="${PHP_VERSION}" --for-extensions="${EXTENSIONS}" --prefer-pre-built

echo "=== Building PHP ${PHP_VERSION} (cli + frankenphp) ==="
$SPC build --build-cli --build-embed --build-frankenphp --enable-zts "${EXTENSIONS}"

echo "=== Packaging ==="

# Create tarball with both binaries
STAGING_DIR="${BUILD_DIR}/staging-${OUTPUT_NAME}"
rm -rf "$STAGING_DIR"
mkdir -p "${STAGING_DIR}/bin"

# Copy PHP CLI binary
if [[ -f "buildroot/bin/php" ]]; then
    cp "buildroot/bin/php" "${STAGING_DIR}/bin/php"
    chmod +x "${STAGING_DIR}/bin/php"
    echo "  PHP CLI: $(du -h buildroot/bin/php | cut -f1)"
else
    echo "ERROR: PHP CLI binary not found at buildroot/bin/php" >&2
    ls -la buildroot/bin/ 2>/dev/null || echo "buildroot/bin/ does not exist"
    exit 1
fi

# Copy FrankenPHP binary
if [[ -f "buildroot/bin/frankenphp" ]]; then
    cp "buildroot/bin/frankenphp" "${STAGING_DIR}/bin/frankenphp"
    chmod +x "${STAGING_DIR}/bin/frankenphp"
    echo "  FrankenPHP: $(du -h buildroot/bin/frankenphp | cut -f1)"
else
    echo "WARNING: FrankenPHP binary not found at buildroot/bin/frankenphp"
    echo "  Continuing with CLI-only build"
fi

# Create tarball
cd "$STAGING_DIR"
tar czf "${OUTPUT_DIR}/${OUTPUT_NAME}.tar.gz" bin/
cd -

rm -rf "$STAGING_DIR"

echo "=== Build complete ==="
echo "Output: ${OUTPUT_DIR}/${OUTPUT_NAME}.tar.gz"
echo "Size: $(du -h "${OUTPUT_DIR}/${OUTPUT_NAME}.tar.gz" | cut -f1)"

echo "=== Verifying PHP CLI ==="
"${BUILD_DIR}/static-php-cli/buildroot/bin/php" -v || echo "Warning: Could not run binary (cross-compiled?)"
