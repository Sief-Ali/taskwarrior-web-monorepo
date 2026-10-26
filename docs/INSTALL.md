# Installing Taskwarrior Web

## Standard installation (Linux x86_64)

The installer downloads the latest stable runtime-only GitHub Release. It does
not clone the source repository or its submodules.

Requirements:

- Linux x86_64/amd64
- Node.js 20.9 or newer
- Taskwarrior configured for the current operating-system user
- `curl`, `tar`, `sha256sum`, `python3`, `systemd` user services, and `ss`
- Local ports 3000 and 5000 available

Download the installer, inspect it if desired, and run it:

```bash
curl --fail --location --show-error \
  https://raw.githubusercontent.com/Sief-Ali/taskwarrior-web-monorepo/master/install.sh \
  --output install.sh
less install.sh
bash install.sh
```

The installer checks the environment, runs `task --version` and `task export`,
retrieves the latest stable release metadata from GitHub, downloads the runtime
archive and checksum, verifies the checksum, validates the archive, installs
the release, creates two systemd **user** services, and checks both HTTP
endpoints before reporting success.

## Install locations

- Releases: `~/.local/opt/taskwarrior-web/releases/<version>/`
- Active release symlink: `~/.local/opt/taskwarrior-web/current`
- User service files: `~/.config/systemd/user/taskwarrior-api.service` and
  `taskwarrior-web.service`

The API and client are separate services. Useful commands:

```bash
systemctl --user status taskwarrior-api.service
systemctl --user status taskwarrior-web.service
journalctl --user -u taskwarrior-api.service -f
journalctl --user -u taskwarrior-web.service -f
```

The installer limits service networking to localhost using systemd's IP
filtering directives. If the local systemd version or security policy does not
support those directives, check `systemctl --user status` and the journal.

By default, user services start with the user's systemd session. To keep them
running from boot even before the user logs in, enable lingering (requires
administrator authorization):

```bash
sudo loginctl enable-linger "$USER"
```

## Updating

Run the same installer again. It fetches the latest stable release, verifies
its checksum, and switches the `current` symlink to the new version. The
installer does not remove older version directories, so you can inspect them
or manually remove old releases after confirming the new version works.

## Release versioning and release notes (maintainers)

The release workflow uses Git tags as the version source. Version tags must
follow `vMAJOR.MINOR.PATCH`, for example `v1.0.1` or `v1.1.0`.

1. Merge the changes intended for the release into `master`.
2. Create and push a new tag from that commit:

   ```bash
   git switch master
   git pull --ff-only
   git tag v1.0.1
   git push origin v1.0.1
   ```

3. GitHub Actions builds the pinned monorepo/submodules, creates the runtime
   archive and SHA-256 checksum, then publishes a GitHub Release.

Do not reuse a published version tag. For a bug fix, increment the patch
number (`v1.0.1`); for a backwards-compatible feature, increment the minor
number (`v1.1.0`); for incompatible changes, increment the major number
(`v2.0.0`).

The workflow already uses `generate_release_notes: true`, so GitHub generates
the release message from changes since the previous release. The optional
`.github/release.yml` file groups merged PRs into Features, Bug Fixes,
Maintenance, and Other Changes based on labels. Add those labels to PRs if
you want them to appear in a specific section. If a release contains no merged
PRs since the previous tag, GitHub may generate a short changelog link instead
of a long message.

## Development installation (source checkout)

The standard installer is for end users. To develop the project, clone the
monorepo with its pinned submodules and install workspace dependencies:

```bash
git clone --recurse-submodules https://github.com/Sief-Ali/taskwarrior-web-monorepo.git
cd taskwarrior-web-monorepo
pnpm install
pnpm dev
```

Build both applications with `pnpm build`; start the production workspace with
`pnpm start`. The API is unauthenticated, so keep it on a trusted machine or
network. Do not expose it to untrusted users without proper access controls.
