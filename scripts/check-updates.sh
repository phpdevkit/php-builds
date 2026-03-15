#!/usr/bin/env bash
#
# check-updates.sh
#
# Resolves the latest patch version for each minor version in config.yaml,
# checks if a GitHub Release already exists, and outputs BUILD or SKIP lines.
#
# Requirements: curl, jq, yq, gh
#
# Output format (one line per version):
#   BUILD 8.4.3
#   SKIP 8.4.3
#   ERROR 8.4 "reason"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"
REPO="${GITHUB_REPOSITORY:-phpdevkit/php-builds}"

# Resolve the latest patch version for a given minor version by querying php.net
resolve_latest_patch() {
    local minor="$1"

    # Query the PHP releases API for the minor version series
    local releases
    releases=$(curl -fsSL "https://www.php.net/releases/index.php?json&version=${minor}" 2>/dev/null) || {
        # Fallback: try the active releases endpoint
        releases=$(curl -fsSL "https://www.php.net/releases/?json&max=50" 2>/dev/null) || {
            echo ""
            return
        }
    }

    # The single-version endpoint returns {"version":"X.Y.Z",...}
    local version
    version=$(echo "$releases" | jq -r '.version // empty' 2>/dev/null)
    if [[ -n "$version" ]]; then
        echo "$version"
        return
    fi

    # The multi-release endpoint returns {"X.Y.Z": {...}, ...}
    # Filter for versions matching our minor, sort descending, take first
    version=$(echo "$releases" | jq -r "keys[]" 2>/dev/null \
        | grep "^${minor}\." \
        | sort -V \
        | tail -n1)

    echo "$version"
}

# Check if a GitHub Release with tag php-{version} exists
release_exists() {
    local version="$1"
    local tag="php-${version}"

    if gh release view "$tag" --repo "$REPO" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

main() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: config.yaml not found at ${CONFIG_FILE}" >&2
        exit 1
    fi

    # Read minor versions from config
    local versions
    versions=$(yq -r '.versions[]' "$CONFIG_FILE")

    while IFS= read -r minor; do
        [[ -z "$minor" ]] && continue

        # Resolve latest patch
        local patch
        patch=$(resolve_latest_patch "$minor")

        if [[ -z "$patch" ]]; then
            echo "ERROR ${minor} \"could not resolve latest patch version\""
            continue
        fi

        # Check if release exists
        if release_exists "$patch"; then
            echo "SKIP ${patch}"
        else
            echo "BUILD ${patch}"
        fi
    done <<< "$versions"
}

main "$@"
