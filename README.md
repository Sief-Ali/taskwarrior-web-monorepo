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

