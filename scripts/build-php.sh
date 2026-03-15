#!/usr/bin/env bash
#
# build-php.sh
#
# Builds a static PHP binary using static-php-cli for a given version, OS, and architecture.
# Packages the result into a tarball.
#
# Usage: ./build-php.sh <version> <os> <arch>
#
# Example: ./build-php.sh 8.4.3 linux x86_64
#
# Output: output/php-{version}-{os}-{arch}.tar.gz

set -euo pipefail

VERSION="${1:?Usage: build-php.sh <version> <os> <arch>}"
OS="${2:?Usage: build-php.sh <version> <os> <arch>}"
ARCH="${3:?Usage: build-php.sh <version> <os> <arch>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
OUTPUT_DIR="${SCRIPT_DIR}/../output"
TARBALL_NAME="php-${VERSION}-${OS}-${ARCH}.tar.gz"

echo "=== Building PHP ${VERSION} for ${OS}-${ARCH} ==="

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Download static-php-cli if not present
SPC_VERSION="2.8.2"
SPC="${BUILD_DIR}/spc"

if [[ ! -x "$SPC" ]]; then
    echo "Downloading static-php-cli ${SPC_VERSION}..."
    local_arch=$(uname -m)
    spc_url="https://github.com/crazywhalecc/static-php-cli/releases/download/${SPC_VERSION}/spc-linux-${local_arch}.tar.gz"
    curl -fsSL "$spc_url" -o "${BUILD_DIR}/spc.tar.gz"
    tar -xzf "${BUILD_DIR}/spc.tar.gz" -C "${BUILD_DIR}/"
    chmod +x "$SPC"
    rm -f "${BUILD_DIR}/spc.tar.gz"
fi

# Install build dependencies (musl-cross-make, etc.)
echo "=== Installing build dependencies ==="
"$SPC" doctor --auto-fix

# Comprehensive extension list
EXT_LIST="bcmath,bz2,calendar,ctype,curl,dom,exif,fileinfo,filter,ftp,gd,gettext,gmp,iconv,intl,mbstring,mysqli,mysqlnd,opcache,openssl,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,posix,readline,redis,session,shmop,simplexml,soap,sockets,sodium,sqlite3,sysvmsg,sysvsem,sysvshm,tokenizer,xml,xmlreader,xmlwriter,xsl,zip,zlib"

echo "Building with extensions: ${EXT_LIST}"

# Step 1: Download PHP source and extension sources
echo "=== Downloading sources ==="
"$SPC" download \
    --with-php="${VERSION}" \
    --for-extensions="${EXT_LIST}" \
    --prefer-pre-built \
    --retry=3

# Step 2: Build static PHP CLI binary
echo "=== Compiling PHP ==="
"$SPC" build \
    --build-cli \
    -L \
    "${EXT_LIST}"

# Step 3: Locate and package the binary
PHP_BINARY="buildroot/bin/php"
if [[ ! -f "$PHP_BINARY" ]]; then
    PHP_BINARY=$(find buildroot -name "php" -type f -executable 2>/dev/null | head -1 || true)
fi

if [[ -z "$PHP_BINARY" || ! -f "$PHP_BINARY" ]]; then
    echo "ERROR: PHP binary not found after build" >&2
    exit 1
fi

echo "PHP binary: ${PHP_BINARY}"

# Create package structure
PACKAGE_DIR="${BUILD_DIR}/package/php-${VERSION}"
mkdir -p "${PACKAGE_DIR}/bin"

cp "$PHP_BINARY" "${PACKAGE_DIR}/bin/php"
chmod +x "${PACKAGE_DIR}/bin/php"

# Copy additional binaries if available
for tool in php-config phpize; do
    tool_path="buildroot/bin/${tool}"
    if [[ -f "$tool_path" ]]; then
        cp "$tool_path" "${PACKAGE_DIR}/bin/${tool}"
        chmod +x "${PACKAGE_DIR}/bin/${tool}"
    fi
done

# Verify
echo "=== Verifying build ==="
"${PACKAGE_DIR}/bin/php" -v || echo "Warning: Could not run PHP binary (cross-compiled?)"

# Create tarball
echo "=== Packaging ==="
tar -czf "${OUTPUT_DIR}/${TARBALL_NAME}" \
    -C "${BUILD_DIR}/package" \
    "php-${VERSION}"

echo "=== Build complete ==="
echo "Output: ${OUTPUT_DIR}/${TARBALL_NAME}"
echo "Size: $(du -h "${OUTPUT_DIR}/${TARBALL_NAME}" | cut -f1)"

# Clean up
rm -rf "${BUILD_DIR}/package" buildroot
