#!/usr/bin/env bash
#
# build-php.sh
#
# Builds a FrankenPHP binary with a specific PHP version embedded.
# Uses FrankenPHP's build-static.sh script.
#
# Usage: ./build-php.sh <php_version> <os> <arch>
#
# Example: ./build-php.sh 8.4.3 linux x86_64
#
# Output: output/frankenphp-{php_version}-{os}-{arch}

set -euo pipefail

PHP_VERSION="${1:?Usage: build-php.sh <php_version> <os> <arch>}"
OS="${2:?Usage: build-php.sh <php_version> <os> <arch>}"
ARCH="${3:?Usage: build-php.sh <php_version> <os> <arch>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"
BUILD_DIR="${SCRIPT_DIR}/../build"
OUTPUT_DIR="${SCRIPT_DIR}/../output"
OUTPUT_NAME="frankenphp-${PHP_VERSION}-${OS}-${ARCH}"

FRANKENPHP_VERSION=$(yq -r '.frankenphp_version' "$CONFIG_FILE")
echo "=== Building FrankenPHP ${FRANKENPHP_VERSION} with PHP ${PHP_VERSION} for ${OS}-${ARCH} ==="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

FRANKENPHP_DIR="${BUILD_DIR}/frankenphp"
if [[ ! -d "$FRANKENPHP_DIR" ]]; then
    echo "Cloning FrankenPHP..."
    git clone --depth 1 --branch "v${FRANKENPHP_VERSION}" \
        https://github.com/dunglas/frankenphp.git "$FRANKENPHP_DIR"
fi

cd "$FRANKENPHP_DIR"

echo "=== Running build-static.sh ==="
export PHP_VERSION
export FRANKENPHP_VERSION="v${FRANKENPHP_VERSION}"

if [[ -f "build-static.sh" ]]; then
    chmod +x build-static.sh
    ./build-static.sh
else
    echo "ERROR: build-static.sh not found in FrankenPHP source" >&2
    exit 1
fi

BINARY="dist/frankenphp-${OS}-${ARCH}"
if [[ ! -f "$BINARY" ]]; then
    BINARY=$(find dist/ -name "frankenphp*" -type f -executable 2>/dev/null | head -1 || true)
fi

if [[ -z "$BINARY" || ! -f "$BINARY" ]]; then
    echo "ERROR: FrankenPHP binary not found after build" >&2
    ls -la dist/ 2>/dev/null || echo "dist/ does not exist"
    exit 1
fi

cp "$BINARY" "${OUTPUT_DIR}/${OUTPUT_NAME}"
chmod +x "${OUTPUT_DIR}/${OUTPUT_NAME}"

echo "=== Build complete ==="
echo "Output: ${OUTPUT_DIR}/${OUTPUT_NAME}"
echo "Size: $(du -h "${OUTPUT_DIR}/${OUTPUT_NAME}" | cut -f1)"

echo "=== Verifying build ==="
"${OUTPUT_DIR}/${OUTPUT_NAME}" php-cli -v || echo "Warning: Could not run binary (cross-compiled?)"