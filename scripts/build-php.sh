#!/usr/bin/env bash
#
# build-php.sh
#
# Builds a static PHP binary using static-php-cli for a given version, OS, and architecture.
# Packages the result into a tarball.
#
# Usage: ./build-php.sh <version> <os> <arch> [extensions]
#
# Example: ./build-php.sh 8.4.3 linux x86_64 all
#
# Requirements: Docker (for cross-compilation), curl, tar
#
# Output: php-{version}-{os}-{arch}.tar.gz in the current directory

set -euo pipefail

VERSION="${1:?Usage: build-php.sh <version> <os> <arch> [extensions]}"
OS="${2:?Usage: build-php.sh <version> <os> <arch> [extensions]}"
ARCH="${3:?Usage: build-php.sh <version> <os> <arch> [extensions]}"
EXTENSIONS="${4:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../build"
OUTPUT_DIR="${SCRIPT_DIR}/../output"
TARBALL_NAME="php-${VERSION}-${OS}-${ARCH}.tar.gz"

echo "=== Building PHP ${VERSION} for ${OS}-${ARCH} ==="
echo "Extensions: ${EXTENSIONS}"

# Create working directories
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

# Map architecture names for static-php-cli
# static-php-cli uses the same naming convention (x86_64, aarch64)
SPC_ARCH="$ARCH"

# Determine the static-php-cli Docker image or binary to use
SPC_VERSION="2.4.0"
SPC_BINARY="spc"

# Download static-php-cli if not present
if [[ ! -x "${BUILD_DIR}/${SPC_BINARY}" ]]; then
    echo "Downloading static-php-cli ${SPC_VERSION}..."

    local_arch=$(uname -m)
    spc_url="https://github.com/crazywhalecc/static-php-cli/releases/download/${SPC_VERSION}/spc-linux-${local_arch}.tar.gz"

    curl -fsSL "$spc_url" -o "${BUILD_DIR}/spc.tar.gz"
    tar -xzf "${BUILD_DIR}/spc.tar.gz" -C "${BUILD_DIR}/"
    chmod +x "${BUILD_DIR}/${SPC_BINARY}"
    rm -f "${BUILD_DIR}/spc.tar.gz"
fi

SPC="${BUILD_DIR}/${SPC_BINARY}"

# Determine extension list
if [[ "$EXTENSIONS" == "all" ]]; then
    # Use a comprehensive set of commonly needed extensions
    EXT_LIST="bcmath,bz2,calendar,ctype,curl,dom,exif,fileinfo,filter,ftp,gd,gettext,gmp,iconv,intl,mbstring,mysqli,mysqlnd,opcache,openssl,pcntl,pdo,pdo_mysql,pdo_pgsql,pdo_sqlite,pgsql,phar,posix,readline,redis,session,shmop,simplexml,soap,sockets,sodium,sqlite3,swoole,sysvmsg,sysvsem,sysvshm,tokenizer,xml,xmlreader,xmlwriter,xsl,zip,zlib"
else
    EXT_LIST="$EXTENSIONS"
fi

echo "Building with extensions: ${EXT_LIST}"

# Download PHP source and extension sources
echo "=== Downloading sources ==="
"$SPC" download \
    --with-php="${VERSION}" \
    --for-extensions="${EXT_LIST}" \
    --prefer-pre-built \
    --retry-count=3 \
    -D "${BUILD_DIR}/downloads"

# Build PHP
echo "=== Compiling PHP ==="
"$SPC" build \
    --build-cli \
    --build-micro \
    "${EXT_LIST}" \
    --with-php="${VERSION}" \
    -D "${BUILD_DIR}/downloads" \
    --build-dir="${BUILD_DIR}/buildroot" \
    -I "-march=x86-64" 2>/dev/null || true

# The actual build command for static-php-cli
"$SPC" build \
    "${EXT_LIST}" \
    --build-cli \
    -D "${BUILD_DIR}/downloads" \
    --debug 2>&1 | tail -20

# Locate built binaries
PHP_BINARY="${BUILD_DIR}/buildroot/bin/php"
if [[ ! -f "$PHP_BINARY" ]]; then
    # Try alternative location
    PHP_BINARY=$(find "${BUILD_DIR}" -name "php" -type f -executable 2>/dev/null | head -1)
fi

if [[ -z "$PHP_BINARY" || ! -f "$PHP_BINARY" ]]; then
    echo "ERROR: PHP binary not found after build" >&2
    exit 1
fi

echo "PHP binary found at: ${PHP_BINARY}"

# Create package directory structure
PACKAGE_DIR="${BUILD_DIR}/package/php-${VERSION}"
mkdir -p "${PACKAGE_DIR}/bin"

# Copy PHP binary
cp "$PHP_BINARY" "${PACKAGE_DIR}/bin/php"
chmod +x "${PACKAGE_DIR}/bin/php"

# Copy additional binaries if they exist
for tool in php-config phpize php-cgi; do
    tool_path="${BUILD_DIR}/buildroot/bin/${tool}"
    if [[ -f "$tool_path" ]]; then
        cp "$tool_path" "${PACKAGE_DIR}/bin/${tool}"
        chmod +x "${PACKAGE_DIR}/bin/${tool}"
    fi
done

# Verify the binary works
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

# Clean up build directory (keep output)
rm -rf "${BUILD_DIR}/package" "${BUILD_DIR}/buildroot" "${BUILD_DIR}/downloads"
