# PHPDevKit PHP Builds

Automated build pipeline for static PHP binaries. This repository builds PHP using [static-php-cli](https://github.com/crazywhalecc/static-php-cli) and publishes binaries to GitHub Releases.

The generated `manifest.json` is consumed by the [PHPDevKit](https://github.com/phpdevkit/phpdevkit) desktop application to discover and install PHP versions.

## How it works

1. A GitHub Actions workflow runs **every hour** (and on manual dispatch)
2. It checks php.net for new patch releases of configured PHP minor versions
3. For each new version, it builds static PHP binaries for all configured platforms
4. Binaries are published as GitHub Release assets
5. A `manifest.json` is regenerated and uploaded to the `latest` release

## Configuration

Edit `config.yaml` to control which versions and platforms are built:

```yaml
versions:
  - "8.2"
  - "8.3"
  - "8.4"
  - "8.5"

platforms:
  - os: linux
    arch: x86_64
  - os: linux
    arch: aarch64

extensions: "all"

tools:
  composer: true
  laravel-installer: true
  symfony-cli: true
```

- **versions**: PHP minor versions to track. The pipeline automatically resolves the latest patch release.
- **platforms**: OS and architecture combinations to build for.
- **extensions**: Set to `"all"` for a comprehensive extension set, or provide a comma-separated list.
- **tools**: Development tools to download and publish alongside PHP.

## Setup

### 1. Create the repository

Create a new GitHub repository (e.g., `phpdevkit/php-builds`) and push this code to it.

### 2. Configure permissions

The workflow needs write access to create releases. Go to:

**Settings > Actions > General > Workflow permissions** and select **Read and write permissions**.

### 3. Manual trigger

To trigger a build manually:

1. Go to **Actions > Build PHP**
2. Click **Run workflow**
3. Optionally specify a version to force-build (e.g., `8.4.3`)

### 4. Verify

After the first successful run:

- Check the **Releases** page for `php-X.Y.Z` releases with tarballs
- Check the `latest` release for `manifest.json`
- Verify the manifest URL works: `https://github.com/<owner>/php-builds/releases/download/latest/manifest.json`

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/check-updates.sh` | Resolves latest patch versions, checks for existing releases |
| `scripts/build-php.sh` | Builds a static PHP binary for a given version/platform |
| `scripts/update-manifest.sh` | Regenerates manifest.json from existing releases |

### Running locally

```bash
# Check which versions need building
./scripts/check-updates.sh

# Build PHP 8.4.3 for Linux x86_64
./scripts/build-php.sh 8.4.3 linux x86_64

# Regenerate manifest
./scripts/update-manifest.sh
```

## Manifest format

The `manifest.json` file has this structure:

```json
{
  "versions": [
    {
      "version": "8.5.1",
      "minor": "8.5",
      "date": "2026-03-10",
      "assets": {
        "linux-x86_64": "https://github.com/phpdevkit/php-builds/releases/download/php-8.5.1/php-8.5.1-linux-x86_64.tar.gz",
        "linux-aarch64": "https://github.com/phpdevkit/php-builds/releases/download/php-8.5.1/php-8.5.1-linux-aarch64.tar.gz"
      }
    }
  ],
  "tools": {
    "composer": {
      "version": "2.8.5",
      "url": "https://github.com/phpdevkit/php-builds/releases/download/tools/composer.phar"
    },
    "laravel-installer": {
      "version": "5.3.0",
      "linux-x86_64": "https://github.com/phpdevkit/php-builds/releases/download/tools/laravel-linux-x86_64",
      "linux-aarch64": "https://github.com/phpdevkit/php-builds/releases/download/tools/laravel-linux-aarch64"
    },
    "symfony-cli": {
      "version": "5.10.6",
      "linux-x86_64": "https://github.com/phpdevkit/php-builds/releases/download/tools/symfony-linux-x86_64",
      "linux-aarch64": "https://github.com/phpdevkit/php-builds/releases/download/tools/symfony-linux-aarch64"
    }
  }
}
```

## Requirements

The build workflow requires these tools (all available on GitHub Actions runners):

- `curl`, `jq` - HTTP requests and JSON processing
- `yq` - YAML processing (installed by the workflow)
- `gh` - GitHub CLI (pre-installed on runners)
- Build tools: `gcc`, `make`, `autoconf`, `cmake`, `re2c`, `bison`

## License

MIT
