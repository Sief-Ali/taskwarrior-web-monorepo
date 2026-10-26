#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

if [[ -z "$VERSION" || ! "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
  echo "Usage: bash scripts/build-release.sh <version>" >&2
  exit 2
fi

for command_name in node pnpm tar gzip sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing build requirement: %s\n' "$command_name" >&2
    exit 1
  fi
done

CONFIG="$ROOT/client/next.config.ts"
if [[ ! -f "$CONFIG" ]]; then
  echo "Client submodule is missing. Check out the repository with recursive submodules." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/taskwarrior-release.XXXXXX")"
CONFIG_BACKUP="$WORK_DIR/next.config.ts.original"
cp -- "$CONFIG" "$CONFIG_BACKUP"

cleanup() {
  cp -- "$CONFIG_BACKUP" "$CONFIG" 2>/dev/null || true
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

cd "$ROOT"

# Enable standalone output for this build only. Restore the checked-out config
# on exit so packaging does not modify the client submodule.
node --input-type=module <<'NODE'
import fs from 'node:fs';

const configPath = 'client/next.config.ts';
let config = fs.readFileSync(configPath, 'utf8');
const marker = 'const nextConfig: NextConfig = {';

if (!config.includes(marker)) {
  throw new Error(`Could not find the expected Next.js config object in ${configPath}`);
}

const outputMatch = config.match(/\boutput\s*:\s*["']([^"']+)["']/);
if (outputMatch && outputMatch[1] !== 'standalone') {
  throw new Error(`Release build requires Next.js output: "standalone", found "${outputMatch[1]}"`);
}

if (!outputMatch) {
  config = config.replace(marker, `${marker}\n  output: "standalone",`);
}

if (!/\boutputFileTracingRoot\s*:/.test(config)) {
  config = config.replace(marker, `${marker}\n  outputFileTracingRoot: workspaceRoot,`);
}

fs.writeFileSync(configPath, config);
NODE

echo "Building API and web client for $VERSION ..."
pnpm build

SERVER_DIST="$ROOT/server/dist/server.js"
CLIENT_STANDALONE="$ROOT/client/.next/standalone"
CLIENT_STATIC="$ROOT/client/.next/static"

if [[ ! -f "$SERVER_DIST" ]]; then
  echo "API build did not produce server/dist/server.js." >&2
  exit 1
fi
if [[ ! -d "$CLIENT_STANDALONE" || ! -d "$CLIENT_STATIC" ]]; then
  echo "Client build did not produce the expected Next.js standalone/static output." >&2
  exit 1
fi

SERVER_DEPLOY="$WORK_DIR/server-deploy"
pnpm --filter=taskwarrior-api --prod deploy "$SERVER_DEPLOY"

if [[ ! -d "$SERVER_DEPLOY/node_modules" ]]; then
  echo "Could not create an isolated production dependency tree for the API." >&2
  exit 1
fi

PACKAGE="$WORK_DIR/package"
mkdir -p "$PACKAGE/server" "$PACKAGE/client"
cp -a "$SERVER_DEPLOY/node_modules" "$PACKAGE/server/node_modules"
cp -a "$ROOT/server/dist" "$PACKAGE/server/dist"

# Do not ship source maps or declaration files with the API bundle.
find "$PACKAGE/server/dist" -type f \( -name '*.map' -o -name '*.d.ts' -o -name '*.d.ts.map' \) -delete

VERSION_FOR_JSON="$VERSION" TARGET_MANIFEST="$PACKAGE/server/package.json" node --input-type=module <<'NODE'
import fs from 'node:fs';

const packageJson = {
  name: 'taskwarrior-api-runtime',
  version: process.env.VERSION_FOR_JSON,
  private: true,
  type: 'module',
  scripts: { start: 'node dist/server.js' },
};
fs.writeFileSync(process.env.TARGET_MANIFEST, JSON.stringify(packageJson, null, 2) + '\n');
NODE

cp -a "$CLIENT_STANDALONE/." "$PACKAGE/client/"

# The tracing root is the monorepo, so the app may be nested under client/.
# Handle both the flat and nested standalone layouts.
if [[ -f "$PACKAGE/client/server.js" ]]; then
  CLIENT_APP="$PACKAGE/client"
elif [[ -f "$PACKAGE/client/client/server.js" ]]; then
  CLIENT_APP="$PACKAGE/client/client"
else
  echo "Could not locate server.js in Next.js standalone output." >&2
  find "$PACKAGE/client" -maxdepth 4 -name server.js -print >&2 || true
  exit 1
fi

mkdir -p "$CLIENT_APP/.next/static"
cp -a "$CLIENT_STATIC/." "$CLIENT_APP/.next/static/"

if [[ -d "$ROOT/client/public" ]]; then
  rm -rf -- "$CLIENT_APP/public"
  cp -a "$ROOT/client/public" "$CLIENT_APP/public"
fi

# Next has compiled first-party application source into .next/server. Remove
# the original source folders and development scaffolding from the runtime app.
for source_dir in src app pages components hooks lib tests __tests__ e2e; do
  rm -rf -- "$CLIENT_APP/$source_dir"
done
rm -f -- "$CLIENT_APP/README.md" "$CLIENT_APP/tsconfig.json" \
  "$CLIENT_APP/tsconfig.tsbuildinfo" "$CLIENT_APP/next-env.d.ts"

# Source maps and local environment files are not required to run the bundle.
find "$PACKAGE" -type f -name '*.map' -delete
find "$PACKAGE" -type f -name '.env' -delete
find "$PACKAGE" -type f -name '.env.*' ! -name '.env.example' -delete

printf '%s\n' "$VERSION" > "$PACKAGE/VERSION"

if [[ ! -f "$PACKAGE/server/dist/server.js" || ! -f "$CLIENT_APP/server.js" ]]; then
  echo "Runtime bundle validation failed: a server entry point is missing." >&2
  exit 1
fi
if [[ -d "$PACKAGE/server/src" || -d "$CLIENT_APP/src" || -d "$CLIENT_APP/app" || -d "$CLIENT_APP/pages" ]]; then
  echo "Runtime bundle validation failed: first-party source directories remain." >&2
  exit 1
fi

OUTPUT_DIR="$ROOT/dist-release"
rm -rf -- "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
ARCHIVE="$OUTPUT_DIR/taskwarrior-web-linux-x64.tar.gz"

tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  -cf - -C "$PACKAGE" . | gzip -n > "$ARCHIVE"
(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo
echo "Runtime bundle created:"
du -h "$ARCHIVE"
echo "The archive contains runtime files only; first-party source folders and source maps are excluded."
echo "Artifacts: $OUTPUT_DIR"
