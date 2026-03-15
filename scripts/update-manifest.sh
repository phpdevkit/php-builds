#!/usr/bin/env bash
#
# update-manifest.sh
#
# Regenerates manifest.json from existing GitHub Releases and uploads it
# to the "latest" release.
#
# Requirements: gh, jq, curl
#
# Usage: ./update-manifest.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"
REPO="${GITHUB_REPOSITORY:-phpdevkit/php-builds}"
MANIFEST_FILE="${SCRIPT_DIR}/../manifest.json"

echo "=== Regenerating manifest.json ==="

# Collect all PHP releases
# Each release is tagged as "php-X.Y.Z" and contains assets like php-X.Y.Z-linux-x86_64.tar.gz
releases=$(gh release list --repo "$REPO" --limit 200 --json tagName,publishedAt 2>/dev/null || echo "[]")

# Build the versions array
versions_json="[]"

while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue

    # Only process php-* tags
    if [[ ! "$tag" =~ ^php-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        continue
    fi

    version="${BASH_REMATCH[1]}"
    minor="${version%.*}"

    # Get release date
    date=$(echo "$releases" | jq -r --arg tag "$tag" '.[] | select(.tagName == $tag) | .publishedAt' | cut -d'T' -f1)
    [[ -z "$date" || "$date" == "null" ]] && date=$(date +%Y-%m-%d)

    # Get release assets
    assets_json=$(gh release view "$tag" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")

    # Build assets map
    assets_map="{}"
    while IFS= read -r asset_name; do
        [[ -z "$asset_name" ]] && continue

        # Match php-X.Y.Z-os-arch.tar.gz
        if [[ "$asset_name" =~ ^php-${version}-([a-z]+)-([a-z0-9_]+)\.tar\.gz$ ]]; then
            os="${BASH_REMATCH[1]}"
            arch="${BASH_REMATCH[2]}"
            platform="${os}-${arch}"
            url="https://github.com/${REPO}/releases/download/${tag}/${asset_name}"
            assets_map=$(echo "$assets_map" | jq --arg platform "$platform" --arg url "$url" '. + {($platform): $url}')
        fi
    done <<< "$assets_json"

    # Skip if no assets found
    if [[ "$assets_map" == "{}" ]]; then
        echo "Warning: No assets found for ${tag}, skipping"
        continue
    fi

    # Add version entry
    version_entry=$(jq -n \
        --arg version "$version" \
        --arg minor "$minor" \
        --arg date "$date" \
        --argjson assets "$assets_map" \
        '{version: $version, minor: $minor, date: $date, assets: $assets}')

    versions_json=$(echo "$versions_json" | jq --argjson entry "$version_entry" '. + [$entry]')

    echo "Found: PHP ${version} (${date})"
done < <(echo "$releases" | jq -r '.[].tagName')

# Sort versions descending (newest first)
versions_json=$(echo "$versions_json" | jq 'sort_by(.version) | reverse')

# Build tools section
echo "=== Collecting tool information ==="
tools_json="{}"

# Check for tools release
tools_release_exists=false
if gh release view "tools" --repo "$REPO" >/dev/null 2>&1; then
    tools_release_exists=true
fi

if [[ "$tools_release_exists" == "true" ]]; then
    tools_assets=$(gh release view "tools" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")

    # Composer
    if echo "$tools_assets" | grep -q "composer.phar"; then
        composer_version=$(gh release view "tools" --repo "$REPO" --json body --jq '.body' 2>/dev/null \
            | grep -oP 'composer[:\s]+\K[0-9]+\.[0-9]+\.[0-9]+' || echo "latest")
        tools_json=$(echo "$tools_json" | jq --arg ver "$composer_version" \
            '. + {"composer": {"version": $ver, "url": "https://github.com/'"${REPO}"'/releases/download/tools/composer.phar"}}')
        echo "Found: Composer ${composer_version}"
    fi

    # Laravel installer
    has_laravel=false
    laravel_json='{"version": "latest"}'
    while IFS= read -r asset_name; do
        if [[ "$asset_name" =~ ^laravel-([a-z]+)-([a-z0-9_]+)$ ]]; then
            os="${BASH_REMATCH[1]}"
            arch="${BASH_REMATCH[2]}"
            platform="${os}-${arch}"
            url="https://github.com/${REPO}/releases/download/tools/${asset_name}"
            laravel_json=$(echo "$laravel_json" | jq --arg platform "$platform" --arg url "$url" '. + {($platform): $url}')
            has_laravel=true
        fi
    done <<< "$tools_assets"
    if [[ "$has_laravel" == "true" ]]; then
        laravel_version=$(gh release view "tools" --repo "$REPO" --json body --jq '.body' 2>/dev/null \
            | grep -oP 'laravel-installer[:\s]+\K[0-9]+\.[0-9]+\.[0-9]+' || echo "latest")
        laravel_json=$(echo "$laravel_json" | jq --arg ver "$laravel_version" '.version = $ver')
        tools_json=$(echo "$tools_json" | jq --argjson laravel "$laravel_json" '. + {"laravel-installer": $laravel}')
        echo "Found: Laravel Installer ${laravel_version}"
    fi

    # Symfony CLI
    has_symfony=false
    symfony_json='{"version": "latest"}'
    while IFS= read -r asset_name; do
        if [[ "$asset_name" =~ ^symfony-([a-z]+)-([a-z0-9_]+)$ ]]; then
            os="${BASH_REMATCH[1]}"
            arch="${BASH_REMATCH[2]}"
            platform="${os}-${arch}"
            url="https://github.com/${REPO}/releases/download/tools/${asset_name}"
            symfony_json=$(echo "$symfony_json" | jq --arg platform "$platform" --arg url "$url" '. + {($platform): $url}')
            has_symfony=true
        fi
    done <<< "$tools_assets"
    if [[ "$has_symfony" == "true" ]]; then
        symfony_version=$(gh release view "tools" --repo "$REPO" --json body --jq '.body' 2>/dev/null \
            | grep -oP 'symfony-cli[:\s]+\K[0-9]+\.[0-9]+\.[0-9]+' || echo "latest")
        symfony_json=$(echo "$symfony_json" | jq --arg ver "$symfony_version" '.version = $ver')
        tools_json=$(echo "$tools_json" | jq --argjson symfony "$symfony_json" '. + {"symfony-cli": $symfony}')
        echo "Found: Symfony CLI ${symfony_version}"
    fi
fi

# Assemble final manifest
manifest=$(jq -n \
    --argjson versions "$versions_json" \
    --argjson tools "$tools_json" \
    '{versions: $versions, tools: $tools}')

echo "$manifest" | jq '.' > "$MANIFEST_FILE"

echo "=== Manifest written to ${MANIFEST_FILE} ==="
echo "Versions: $(echo "$manifest" | jq '.versions | length')"
echo "Tools: $(echo "$manifest" | jq '.tools | keys | length')"

# Upload to "latest" release
echo "=== Uploading manifest to 'latest' release ==="

# Create "latest" release if it doesn't exist
if ! gh release view "latest" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "latest" \
        --repo "$REPO" \
        --title "Latest Manifest" \
        --notes "Auto-generated release containing manifest.json. This release is updated automatically." \
        --latest=false
fi

# Upload/overwrite manifest.json
gh release upload "latest" \
    "$MANIFEST_FILE" \
    --repo "$REPO" \
    --clobber

echo "=== Done ==="
echo "Manifest URL: https://github.com/${REPO}/releases/download/latest/manifest.json"
