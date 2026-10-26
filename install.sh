#!/usr/bin/env bash
set -Eeuo pipefail

REPOSITORY="Sief-Ali/taskwarrior-web-monorepo"
ASSET_NAME="taskwarrior-web-linux-x64.tar.gz"
INSTALL_ROOT="${HOME}/.local/opt/taskwarrior-web"
SERVICE_DIR="${HOME}/.config/systemd/user"
API_SERVICE="taskwarrior-api.service"
WEB_SERVICE="taskwarrior-web.service"
NODE_BIN=""
TASK_BIN=""
TMP_DIR=""
OLD_CURRENT=""
OLD_API_ACTIVE=0
OLD_WEB_ACTIVE=0
SWITCHED_CURRENT=0
INSTALL_COMPLETE=0

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

note() {
  printf '\n==> %s\n' "$*"
}

uninstall() {
  local failed=0
  local service

  note "Uninstalling Taskwarrior Web"

  # Stop and disable the application's user services.
  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user stop "$WEB_SERVICE" "$API_SERVICE"; then
      echo "Warning: Could not confirm that both services stopped." >&2
      echo "If they are still running, stop them manually." >&2
    fi

    systemctl --user disable "$WEB_SERVICE" "$API_SERVICE" \
      >/dev/null 2>&1 || true
  fi

  # Remove the service definitions.
  for service in "$WEB_SERVICE" "$API_SERVICE"; do
    if ! rm -f -- "$SERVICE_DIR/$service"; then
      printf 'Could not remove: %s\n' "$SERVICE_DIR/$service" >&2
      failed=1
    fi
  done

  # Tell systemd to forget the removed service definitions.
  if command -v systemctl >/dev/null 2>&1; then
    if ! systemctl --user daemon-reload; then
      echo "Warning: Could not reload the systemd user manager." >&2
      echo "Run: systemctl --user daemon-reload" >&2
    fi
  fi

  # Remove application releases, current symlink, and rollback leftovers.
  if [[ -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ]]; then
    if ! rm -rf -- "$INSTALL_ROOT"; then
      printf 'Could not completely remove: %s\n' "$INSTALL_ROOT" >&2
      failed=1
    fi
  fi

  # Check whether any application files remain.
  if [[ -e "$INSTALL_ROOT" || -L "$INSTALL_ROOT" ]]; then
    failed=1
  fi

  for service in "$WEB_SERVICE" "$API_SERVICE"; do
    if [[ -e "$SERVICE_DIR/$service" || -L "$SERVICE_DIR/$service" ]]; then
      failed=1
    fi
  done

  if (( failed )); then
    echo
    echo "Uninstallation was incomplete. Check these paths manually:"
    printf '  Application: %s\n' "$INSTALL_ROOT"
    printf '  Services:    %s/%s\n' "$SERVICE_DIR" "$WEB_SERVICE"
    printf '               %s/%s\n' "$SERVICE_DIR" "$API_SERVICE"
    echo "Remove any remaining files only after confirming the services are stopped."
    return 1
  fi

  note "Taskwarrior Web has been uninstalled"
  echo "Your Taskwarrior tasks and configuration have not been removed."
}

is_active() {
  systemctl --user is-active --quiet "$1"
}

cleanup() {
  status=$?
  if [[ "$INSTALL_COMPLETE" != "1" ]]; then
    if [[ "$SWITCHED_CURRENT" == "1" ]]; then
      echo "Installation did not complete; attempting to restore the previous version..." >&2
      systemctl --user stop "$WEB_SERVICE" "$API_SERVICE" >/dev/null 2>&1 || true

      if [[ -n "$OLD_CURRENT" && -d "$OLD_CURRENT" ]]; then
        ln -sfn "$OLD_CURRENT" "$INSTALL_ROOT/current.rollback"
        mv -Tf "$INSTALL_ROOT/current.rollback" "$INSTALL_ROOT/current"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
        if [[ "$OLD_API_ACTIVE" == "1" ]]; then
          systemctl --user start "$API_SERVICE" >/dev/null 2>&1 || true
        fi
        if [[ "$OLD_WEB_ACTIVE" == "1" ]]; then
          systemctl --user start "$WEB_SERVICE" >/dev/null 2>&1 || true
        fi
      else
        systemctl --user disable --now "$WEB_SERVICE" "$API_SERVICE" >/dev/null 2>&1 || true
        rm -f "$SERVICE_DIR/$WEB_SERVICE" "$SERVICE_DIR/$API_SERVICE"
        rm -f "$INSTALL_ROOT/current"
        systemctl --user daemon-reload >/dev/null 2>&1 || true
      fi
    elif [[ -n "$OLD_CURRENT" && -d "$OLD_CURRENT" ]]; then
      # A failure before switching releases should not leave a working install stopped.
      if [[ "$OLD_API_ACTIVE" == "1" ]]; then
        systemctl --user start "$API_SERVICE" >/dev/null 2>&1 || true
      fi
      if [[ "$OLD_WEB_ACTIVE" == "1" ]]; then
        systemctl --user start "$WEB_SERVICE" >/dev/null 2>&1 || true
      fi
    fi
  fi

  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  exit "$status"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  [[ "$#" -eq 1 ]] || die "Usage: bash install.sh --uninstall"
  uninstall
  exit $?
fi

trap cleanup EXIT

check_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' is missing."
}

note "Checking operating system and requirements"
[[ "$(uname -s)" == "Linux" ]] || die "This release installer currently supports Linux only."
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "This release currently supports x86_64/amd64 Linux only." ;;
esac

for command_name in curl tar sha256sum python3 node task systemctl ss awk; do
  check_command "$command_name"
done

NODE_BIN="$(command -v node)"
TASK_BIN="$(command -v task)"

NODE_VERSION="$("$NODE_BIN" -p 'process.versions.node')"
IFS='.' read -r NODE_MAJOR NODE_MINOR _ <<< "$NODE_VERSION"
[[ "$NODE_MAJOR" =~ ^[0-9]+$ && "$NODE_MINOR" =~ ^[0-9]+$ ]] || die "Could not parse Node.js version: $NODE_VERSION"
if (( NODE_MAJOR < 20 || (NODE_MAJOR == 20 && NODE_MINOR < 9) )); then
  die "Node.js 20.9 or newer is required; found $NODE_VERSION."
fi

task --version || die "Taskwarrior did not start correctly."
task export >/dev/null || die "Taskwarrior 'task export' failed. Check this user's Taskwarrior configuration."

systemctl --user show-environment >/dev/null 2>&1 ||
  die "The systemd user manager is unavailable. Log in to a graphical or regular user session and retry."

note "Checking ports 3000 and 5000"
OLD_API_ACTIVE=0
OLD_WEB_ACTIVE=0
is_active "$API_SERVICE" && OLD_API_ACTIVE=1 || true
is_active "$WEB_SERVICE" && OLD_WEB_ACTIVE=1 || true

check_port() {
  local port="$1"
  local owning_service="$2"
  local listeners
  listeners="$(ss -ltnH | awk -v suffix=":$port" '$4 ~ (suffix "$") { print $4 }')"
  if [[ -n "$listeners" ]]; then
    if [[ "$owning_service" == "$API_SERVICE" && "$OLD_API_ACTIVE" == "1" ]]; then
      return 0
    fi
    if [[ "$owning_service" == "$WEB_SERVICE" && "$OLD_WEB_ACTIVE" == "1" ]]; then
      return 0
    fi
    die "Port $port is already in use ($listeners). Stop the other application and retry."
  fi
}
check_port 3000 "$WEB_SERVICE"
check_port 5000 "$API_SERVICE"

TMP_DIR="$(mktemp -d)"
RELEASE_JSON="$TMP_DIR/latest-release.json"
ARCHIVE_PATH="$TMP_DIR/$ASSET_NAME"
CHECKSUM_PATH="$TMP_DIR/$ASSET_NAME.sha256"

note "Finding the latest stable GitHub release"
curl --fail --silent --show-error --location \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' \
  "https://api.github.com/repos/$REPOSITORY/releases/latest" \
  --output "$RELEASE_JSON" || die "Could not retrieve the latest GitHub release."

RELEASE_VERSION="$(python3 - "$RELEASE_JSON" "$ASSET_NAME" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
version = release.get("tag_name", "")
if release.get("draft") or release.get("prerelease"):
    raise SystemExit("Latest release is not a stable published release.")
if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?", version):
    raise SystemExit(f"Release tag is not a supported version: {version!r}")
print(version)
PY
)" || die "The latest release metadata is invalid."

ASSET_URL="$(python3 - "$RELEASE_JSON" "$ASSET_NAME" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
for asset in release.get("assets", []):
    if asset.get("name") == sys.argv[2]:
        print(asset.get("browser_download_url", ""))
        break
PY
)"
CHECKSUM_URL="$(python3 - "$RELEASE_JSON" "$ASSET_NAME.sha256" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    release = json.load(f)
for asset in release.get("assets", []):
    if asset.get("name") == sys.argv[2]:
        print(asset.get("browser_download_url", ""))
        break
PY
)"

[[ "$ASSET_URL" == https://github.com/* ]] || die "Release asset '$ASSET_NAME' was not found."
[[ "$CHECKSUM_URL" == https://github.com/* ]] || die "Release checksum '$ASSET_NAME.sha256' was not found."

note "Downloading Taskwarrior Web $RELEASE_VERSION"
curl --fail --silent --show-error --location "$ASSET_URL" --output "$ARCHIVE_PATH" ||
  die "Could not download the release archive."
curl --fail --silent --show-error --location "$CHECKSUM_URL" --output "$CHECKSUM_PATH" ||
  die "Could not download the release checksum."

(
  cd "$TMP_DIR"
  sha256sum --check --status "$CHECKSUM_PATH"
) || die "Release checksum verification failed; refusing to install."

note "Validating release archive"
tar -tzf "$ARCHIVE_PATH" > "$TMP_DIR/archive-files.txt" ||
  die "The downloaded file is not a valid gzip archive."
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$TMP_DIR/archive-files.txt"; then
  die "Release archive contains an unsafe path."
fi

mkdir -p "$TMP_DIR/extracted"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR/extracted" ||
  die "Could not extract the release archive."

PACKAGE_DIR="$TMP_DIR/extracted"
[[ -f "$PACKAGE_DIR/server/dist/server.js" ]] ||
  die "Release archive is missing the compiled API entry point."

if [[ -f "$PACKAGE_DIR/client/server.js" ]]; then
  CLIENT_APP_REL="client"
elif [[ -f "$PACKAGE_DIR/client/client/server.js" ]]; then
  CLIENT_APP_REL="client/client"
else
  die "Release archive is missing the Next.js standalone server entry point."
fi

[[ -d "$PACKAGE_DIR/server/node_modules" ]] ||
  die "Release archive is missing API production dependencies."

note "Installing into $INSTALL_ROOT/releases/$RELEASE_VERSION"
mkdir -p "$INSTALL_ROOT/releases" "$SERVICE_DIR"
OLD_CURRENT="$(readlink -f "$INSTALL_ROOT/current" 2>/dev/null || true)"

# Stop the app before switching the current release symlink.
systemctl --user stop "$WEB_SERVICE" "$API_SERVICE" >/dev/null 2>&1 || true

# Recheck ports after stopping our own services, so unrelated listeners are not
# mistaken for the app being upgraded.
for port in 3000 5000; do
  listeners="$(ss -ltnH | awk -v suffix=":$port" '$4 ~ (suffix "$") { print $4 }')"
  [[ -z "$listeners" ]] || die "Port $port is still occupied after stopping the app ($listeners)."
done

RELEASE_DIR="$INSTALL_ROOT/releases/$RELEASE_VERSION"
if [[ -e "$RELEASE_DIR" && "$OLD_CURRENT" == "$RELEASE_DIR" ]]; then
  # Reinstalling the already-active version: keep its directory so rollback
  # never points at a directory that has just been deleted.
  :
else
  if [[ -e "$RELEASE_DIR" ]]; then
    rm -rf -- "$RELEASE_DIR"
  fi
  mv "$PACKAGE_DIR" "$RELEASE_DIR"
fi

# Write separate user services so each process can restart independently.
cat > "$SERVICE_DIR/$API_SERVICE" <<EOF
[Unit]
Description=Taskwarrior Web API
After=network.target

[Service]
Type=simple
WorkingDirectory=%h/.local/opt/taskwarrior-web/current/server
Environment=NODE_ENV=production
Environment=API_PREFIX=/v1
Environment=PORT=5000
Environment=CORS_ORIGIN=http://localhost:3000
Environment="TASKWARRIOR_COMMAND=$TASK_BIN"
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
IPAddressDeny=any
IPAddressAllow=localhost
ExecStart=$NODE_BIN %h/.local/opt/taskwarrior-web/current/server/dist/server.js

[Install]
WantedBy=default.target
EOF

cat > "$SERVICE_DIR/$WEB_SERVICE" <<EOF
[Unit]
Description=Taskwarrior Web Client
After=network.target $API_SERVICE
Wants=$API_SERVICE

[Service]
Type=simple
WorkingDirectory=%h/.local/opt/taskwarrior-web/current/$CLIENT_APP_REL
Environment=NODE_ENV=production
Environment=HOSTNAME=127.0.0.1
Environment=PORT=3000
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
IPAddressDeny=any
IPAddressAllow=localhost
ExecStart=$NODE_BIN %h/.local/opt/taskwarrior-web/current/$CLIENT_APP_REL/server.js

[Install]
WantedBy=default.target
EOF

ln -sfn "$RELEASE_DIR" "$INSTALL_ROOT/current.new"
mv -Tf "$INSTALL_ROOT/current.new" "$INSTALL_ROOT/current"
SWITCHED_CURRENT=1

note "Enabling and starting services"
systemctl --user daemon-reload
systemctl --user enable "$API_SERVICE" "$WEB_SERVICE"
systemctl --user start "$API_SERVICE"
systemctl --user start "$WEB_SERVICE"

note "Checking application health"
API_OK=0
WEB_OK=0
for _ in {1..20}; do
  if curl --silent --fail http://127.0.0.1:5000/v1/health >/dev/null; then API_OK=1; fi
  if curl --silent --fail http://127.0.0.1:3000/ >/dev/null; then WEB_OK=1; fi
  [[ "$API_OK" == "1" && "$WEB_OK" == "1" ]] && break
  sleep 1
done

[[ "$API_OK" == "1" ]] || die "API health check failed. Inspect: journalctl --user -u $API_SERVICE -n 100"
[[ "$WEB_OK" == "1" ]] || die "Web client health check failed. Inspect: journalctl --user -u $WEB_SERVICE -n 100"

INSTALL_COMPLETE=1
note "Taskwarrior Web $RELEASE_VERSION is installed and running"
printf 'Web UI:       http://localhost:3000\n'
printf 'API health:   http://localhost:5000/v1/health\n'
printf 'Install path: %s\n' "$INSTALL_ROOT/current"
printf 'API status:   systemctl --user status %s\n' "$API_SERVICE"
printf 'Web status:   systemctl --user status %s\n' "$WEB_SERVICE"
printf 'API logs:     journalctl --user -u %s -f\n' "$API_SERVICE"
printf 'Web logs:     journalctl --user -u %s -f\n' "$WEB_SERVICE"
printf '\nServices start when this user session starts. To start them at boot without logging in:\n'
printf '  sudo loginctl enable-linger %q\n' "$USER"
