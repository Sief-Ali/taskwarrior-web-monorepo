# Taskwarrior Web

A web interface for Taskwarrior, backed by the [Taskwarrior API](https://github.com/Sief-Ali/taskwarrior-api).

## End-user installation

The supported release installer currently targets **Linux x86_64/amd64**. It checks the environment, downloads the latest stable runtime-only GitHub Release, verifies its SHA-256 checksum, and installs two systemd user services. It does not clone the source repository or its submodules.

Requirements:

- Node.js 20.9 or newer
- Taskwarrior installed and configured for the current user
- `curl`, `tar`, `sha256sum`, `python3`, `systemd` user services, and `ss`
- Local ports 3000 and 5000 available

Download and run the installer:

```bash
curl --fail --location --show-error \
  https://raw.githubusercontent.com/Sief-Ali/taskwarrior-web-monorepo/master/install.sh \
  --output install.sh
less install.sh
bash install.sh
```

Open <http://localhost:3000> after installation.

### Manage the services

```bash
systemctl --user status taskwarrior-api.service
systemctl --user status taskwarrior-web.service

journalctl --user -u taskwarrior-api.service -f
journalctl --user -u taskwarrior-web.service -f
```

Services start when the user's systemd session starts. To keep them running at boot even before logging in, run `sudo loginctl enable-linger "$USER"` (administrator authorization required).

See [docs/INSTALL.md](docs/INSTALL.md) for installation paths, upgrades, troubleshooting, release versioning, and release notes.

## Development corner

The following setup is for developers who want to modify the source code. End users do not need to clone the repository or submodules.

### Requirements

- Git with submodule support
- Node.js 20.9 or newer
- pnpm 12.14.0
- Taskwarrior installed and configured for the operating-system user who runs the API
- Free local ports 3000 and 5000

### Clone the source repository and submodules

```bash
git clone --recurse-submodules https://github.com/Sief-Ali/taskwarrior-web-monorepo.git
cd taskwarrior-web-monorepo
```

If the project was cloned without submodules:

```bash
git submodule update --init --recursive
git submodule status
```

### Install dependencies

```bash
npm install --global pnpm@12.14.0
pnpm install
```

### Check Taskwarrior

Run as the same OS user that will run the API:

```bash
task --version
task export
```

The API's create, edit, complete, start, stop, and delete actions make real changes to that user's Taskwarrior data. Use a separate Taskwarrior data directory for experiments if you do not want to change personal tasks.

### Configure the API and client

Create the API environment file:

```bash
cp server/.env.example server/.env
```

The default API port is `5000`, the route prefix is `/v1`, and the Taskwarrior command is `task`. The client defaults to `http://localhost:5000/v1`.

To override the client API URL, create `client/.env.local`:

```dotenv
NEXT_PUBLIC_TASKWARRIOR_API_URL=http://localhost:5000/v1
```

### Run in development

From the monorepo root:

```bash
pnpm dev
```

Or run one side at a time:

```bash
pnpm dev:server
pnpm dev:client
```

### Build and run production locally

```bash
pnpm build
pnpm start
```

## Security

The API has no authentication or authorization. Keep it on a trusted machine and do not expose it to untrusted networks without suitable access controls. CORS is not authentication.
