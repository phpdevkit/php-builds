#!/usr/bin/env bash
#
# update-manifest.sh
#
# Regenerates manifest.json from existing GitHub Releases and uploads it
# to the "latest" release. No tools section — tools are fetched at runtime.
#
# Requirements: gh, jq, yq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"
REPO="${GITHUB_REPOSITORY:-phpdevkit/php-builds}"
MANIFEST_FILE="${SCRIPT_DIR}/../manifest.json"

FRANKENPHP_VERSION=$(yq -r '.frankenphp_version' "$CONFIG_FILE")

echo "=== Regenerating manifest.json ==="

releases=$(gh release list --repo "$REPO" --limit 200 --json tagName,publishedAt 2>/dev/null || echo "[]")

versions_json="[]"

while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue

    if [[ ! "$tag" =~ ^php-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        continue
    fi

    version="${BASH_REMATCH[1]}"
    minor="${version%.*}"

    date=$(echo "$releases" | jq -r --arg tag "$tag" '.[] | select(.tagName == $tag) | .publishedAt' | cut -d'T' -f1)
    [[ -z "$date" || "$date" == "null" ]] && date=$(date +%Y-%m-%d)

    assets_json=$(gh release view "$tag" --repo "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || echo "")

    assets_map="{}"
    while IFS= read -r asset_name; do
        [[ -z "$asset_name" ]] && continue

        if [[ "$asset_name" =~ ^frankenphp-${version}-([a-z]+)-([a-z0-9_]+)$ ]]; then
            os="${BASH_REMATCH[1]}"
            arch="${BASH_REMATCH[2]}"
            platform="${os}-${arch}"
            url="https://github.com/${REPO}/releases/download/${tag}/${asset_name}"
            assets_map=$(echo "$assets_map" | jq --arg platform "$platform" --arg url "$url" '. + {($platform): $url}')
        fi
    done <<< "$assets_json"

    if [[ "$assets_map" == "{}" ]]; then
        echo "Warning: No assets found for ${tag}, skipping"
        continue
    fi

    version_entry=$(jq -n \
        --arg version "$version" \
        --arg minor "$minor" \
        --arg fpv "$FRANKENPHP_VERSION" \
        --arg date "$date" \
        --argjson assets "$assets_map" \
        '{version: $version, minor: $minor, frankenphp_version: $fpv, date: $date, assets: $assets}')

    versions_json=$(echo "$versions_json" | jq --argjson entry "$version_entry" '. + [$entry]')

    echo "Found: PHP ${version} (FrankenPHP ${FRANKENPHP_VERSION}, ${date})"
done < <(echo "$releases" | jq -r '.[].tagName')

versions_json=$(echo "$versions_json" | jq 'sort_by(.version) | reverse')

manifest=$(jq -n --argjson versions "$versions_json" '{versions: $versions}')

echo "$manifest" | jq '.' > "$MANIFEST_FILE"

echo "=== Manifest written to ${MANIFEST_FILE} ==="
echo "Versions: $(echo "$manifest" | jq '.versions | length')"

echo "=== Uploading manifest to 'latest' release ==="

if ! gh release view "latest" --repo "$REPO" >/dev/null 2>&1; then
    gh release create "latest" \
        --repo "$REPO" \
        --title "Latest Manifest" \
        --notes "Auto-generated release containing manifest.json." \
        --latest=false
fi

gh release upload "latest" \
    "$MANIFEST_FILE" \
    --repo "$REPO" \
    --clobber

echo "=== Done ==="
echo "Manifest URL: https://github.com/${REPO}/releases/download/latest/manifest.json"
