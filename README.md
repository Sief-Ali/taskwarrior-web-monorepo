# TaskWarrior Web and API

This top-level workspace is a convenience layer for running the TaskWarrior
API and web client together. The API is in `server/` and the Next.js client is
in `client/`.

The workspace adds root-level install and run commands. It keeps each folder's
existing package manifest, lockfile, workspace settings, Git repository, and
folder-level commands intact. You can continue working with either project on
its own from its folder.

## What runs where

```text
Browser (http://localhost:3000)
        |
        | HTTP requests to /v1
        v
TaskWarrior API (http://localhost:5000/v1)
        |
        v
Taskwarrior CLI and the data directory of the API process user
```

Taskwarrior remains the source of truth. The API does not maintain a separate
task database. The web client reads task data and sends create, edit, and
lifecycle requests to the API.

## Requirements

- Node.js `20.9.0` or newer. This satisfies the Next.js 16 client requirement
  and the API's Node.js 20+ requirement.
- pnpm `12.14.0` (the version declared by the project).
- Taskwarrior installed and configured for the operating system account that
  runs the API. The `task` command must be available on that account's `PATH`.
- A browser for the client, and free local ports `3000` (client) and `5000`
  (API), unless you change the configuration.

Check the Taskwarrior installation as the same user who will start the API:

```bash
task --version
task export
```

`task export` reads that user's task data. Use an isolated Taskwarrior
configuration and data directory when developing or verifying mutations if you
do not want to change personal tasks.

## Install the workspace

From this project directory:

```bash
pnpm install
```

The root `pnpm-workspace.yaml` includes `client` and `server`. The root
`pnpm-lock.yaml` describes the combined workspace install. The separate
folder-level manifests, workspace settings, and lockfiles remain available:
run pnpm from the project root to use the combined workspace, or from inside
`client/` or `server/` to use that folder's standalone setup.

## Configure the API and client

Create the API environment file:

```bash
cp server/.env.example server/.env
```

The defaults run the API in development mode on port `5000`, use the `/v1`
prefix, allow the local client origins, and invoke Taskwarrior as `task`.
Review `server/.env` before starting the API. `TASKWARRIOR_COMMAND` is
documented in the example, but the current API does not pass that setting into
the adapter; the adapter uses its default `task` executable.

The client defaults to `http://localhost:5000/v1`. To override that URL, create
`client/.env.local`:

```dotenv
NEXT_PUBLIC_TASKWARRIOR_API_URL=http://localhost:5000/v1
```

The API's configured CORS origins must include the browser origin used by the
client. The default API configuration allows `http://localhost:3000` and
`http://127.0.0.1:3000`.

## Run both applications

Start the development servers together from the project directory:

```bash
pnpm dev
```

The client is available at <http://localhost:3000>. The API health endpoint is
<http://localhost:5000/v1/health>, and Swagger UI is at
<http://localhost:5000/v1/api-docs>.

Or run either application separately in its own terminal:

```bash
pnpm dev:server
pnpm dev:client
```

The equivalent folder-level commands remain available:

```bash
cd server && pnpm dev
cd client && pnpm dev
```

## Build, test, and lint

Run combined workspace commands from the project directory:

```bash
pnpm build
pnpm test
pnpm lint
```

`pnpm build` builds the API and then the client. `pnpm test` runs the API Jest
suite; the client does not currently define a test script. `pnpm lint` runs
both projects' linters. To build or check one project directly:

```bash
pnpm --filter ./server build
pnpm --filter ./server test
pnpm --filter ./client build
pnpm --filter ./client lint
```

After building, start both production servers with `pnpm start`, or start an
individual package with `pnpm --filter ./server start` or
`pnpm --filter ./client start`.

## API operations

The API uses the `/v1` prefix by default:

- `GET /v1/health`, `GET /v1/tasks`, and `GET /v1/tasks/:uuid` read status and
  task data.
- `POST /v1/tasks` creates a task. The description is required; project,
  priority, due date, and tags are optional.
- `PATCH /v1/tasks/:uuid` modifies supported task fields or adds/removes tags.
- `POST /v1/tasks/:uuid/complete`, `POST /v1/tasks/:uuid/start`, and
  `POST /v1/tasks/:uuid/stop` update task lifecycle state.
- `DELETE /v1/tasks/:uuid` marks a task deleted in Taskwarrior. This is a
  recoverable soft-delete, not a purge.

Successful mutations return `204 No Content`. The client refreshes task data
from the API after success.

## Security

The API has no authentication or authorization, and its mutation routes make
real changes to the Taskwarrior data available to the API process. Keep it on a
trusted network or protect it with deployment-level access controls before
exposing it to other users. CORS does not provide authentication or access
control.

## Using the folders as Git submodules

The `client/` and `server/` directories are independent Git repositories.
Having a `.git` directory inside each one does not automatically register it
with a parent repository. A parent repository must track each folder as a
submodule; it records the child repository URL and the exact commit to use.

### One-time setup in the parent repository

First make sure the client and server commits you want to include are pushed to
their respective remotes. Keep a backup of the existing folders, including any
local environment files, before replacing the embedded clones. Run these
commands from the parent repository after it has been initialized and has an
initial commit:

```bash
mv client ../taskwarrior-client-backup
mv server ../taskwarrior-api-backup
git submodule add https://github.com/Sief-Ali/taskwarrior-web.git client
git submodule add https://github.com/Sief-Ali/taskwarrior-api.git server
git add .gitmodules client server
git commit -m "chore: add client and server submodules"
```

Restore local `.env` files from the backups as needed; they are intentionally
ignored and should not be committed. The root `pnpm-workspace.yaml`, root
`package.json`, and root lockfile stay in the parent checkout.

If the parent repository or a backup already exists, adapt the paths first and
verify them with `git status`. The move commands above replace the two
directories with fresh clones from the child remotes, so do not run them until
the current folders are backed up and the desired child commits are available
on those remotes.

### Clone and initialize submodules

To clone the parent and fetch both child repositories in one step:

```bash
git clone --recurse-submodules <parent-repository-url>
```

If the parent has already been cloned without its children:

```bash
git submodule update --init --recursive
```

After pulling a parent commit that updates a submodule pointer, use the same
`git submodule update --init --recursive` command to check out the recorded
child commits.

### Repair a submodule entry with no URL

If `git submodule update` reports `No url found for submodule path 'client' in
.gitmodules`, the parent index already contains a `client` gitlink, but the
`.gitmodules` file is missing its path-to-URL mapping. Register the URL, then
initialize the child:

```bash
git config -f .gitmodules submodule.client.path client
git config -f .gitmodules submodule.client.url https://github.com/Sief-Ali/taskwarrior-web.git
git add .gitmodules
git submodule sync -- client
git submodule update --init client
```

If `server` is also recorded as a submodule and has the same problem, register
it with `submodule.server.path=server` and URL
`https://github.com/Sief-Ali/taskwarrior-api.git`, then run
`git submodule sync -- server` and `git submodule update --init server`.
Once initialized, a submodule is often checked out at the parent's pinned
commit (detached HEAD). To make client changes on its remote `main` branch,
switch to a tracking branch with:

```bash
git -C client switch --track -c main origin/main
```

The parent must then record any new child commit with `git add client` from the
parent directory and commit that pointer update.

### Make and publish changes

Commit and push code changes from inside the relevant child repository. Then
record the new child commit in the parent repository:

```bash
cd client
git switch main
# edit, commit, and push the client changes
cd ..
git add client
git commit -m "chore: update client submodule"
```

Use `cd server` and `git add server` for server changes. The parent commit only
updates the pinned child commit; it does not contain the submodule's source
files. To intentionally move a submodule to the latest remote branch commit,
run `git submodule update --remote client` (or `server`) and then commit that
updated pointer in the parent.

