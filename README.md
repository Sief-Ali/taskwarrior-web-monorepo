# TaskWarrior Web Monorepo

This project brings together the TaskWarrior API and its web client. The API
and client are Git submodules with their own repositories; this parent repo
pins the versions used together.

## Requirements

- Git with submodule support.
- Node.js `20.9.0` or newer.
- pnpm `12.14.0`.
- Taskwarrior installed and configured for the operating system user who runs
  the API. The `task` command must be available on that user's `PATH`.
- Free local ports `3000` and `5000` for the web client and API.

## 1. Clone the project

Clone the parent repository and both submodules:

```bash
git clone --recurse-submodules https://github.com/Sief-Ali/taskwarrior-web-monorepo.git
cd taskwarrior-web-monorepo
```

If you already cloned the parent without its submodules, load them with:

```bash
git submodule update --init --recursive
```

Check that both folders were populated:

```bash
git submodule status
```

The output should list entries for `client` and `server`.

## 2. Install pnpm and project dependencies

Install the required pnpm version if it is not already available:

```bash
npm install --global pnpm@12.14.0
pnpm --version
```

From the monorepo root, install dependencies for the workspace:

```bash
pnpm install
```

## 3. Check Taskwarrior

Run these commands as the same operating system user that will run the API:

```bash
task --version
task export
```

The API uses that user's Taskwarrior configuration and data directory. Its
create, edit, complete, start, stop, and delete actions make real changes to
that data. Use a separate Taskwarrior data directory if you want to try the
app without changing your personal tasks.

## 4. Configure the API and client

Create the API's local environment file:

```bash
cp server/.env.example server/.env
```

The defaults use API port `5000`, the `/v1` route prefix, and the Taskwarrior
command `task`. The default CORS configuration allows the local client at
`http://localhost:3000` and `http://127.0.0.1:3000`.

The client defaults to `http://localhost:5000/v1`. To use a different API URL,
create `client/.env.local` with:

```dotenv
NEXT_PUBLIC_TASKWARRIOR_API_URL=http://localhost:5000/v1
```

Change the value to the API base URL when using a different host or port. The
API's CORS configuration must allow the URL origin where the browser loads the
client. Restart the apps after changing environment files.

## 5. Run the monorepo

Start the API and web client together from the monorepo root:

```bash
pnpm dev
```

Open the client at <http://localhost:3000>. The API health endpoint is
<http://localhost:5000/v1/health>, and its interactive API documentation is at
<http://localhost:5000/v1/api-docs>.

To run only one app, use the corresponding command from the monorepo root:

```bash
pnpm dev:server
pnpm dev:client
```

## 6. Build and run for production

Build both apps from the monorepo root:

```bash
pnpm build
```

Then start both production servers:

```bash
pnpm start
```

## Security

The API does not provide authentication or authorization. Keep it on a trusted
network or protect it with deployment-level access controls before exposing it
to other users. CORS is not authentication or access control.
