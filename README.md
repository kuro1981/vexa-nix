# vexa-nix

Nix packaging and development entrypoints for the [Vexa](https://github.com/vexa-ai/vexa) meeting stack.

The flake pins the Vexa source tree by commit and content hash. Runtime Python and Node dependencies remain governed by Vexa's upstream `uv.lock` files and `pnpm-lock.yaml`; the Nix development shell supplies the exact toolchain needed to consume those locks.

## Run the pinned stack

Docker and a running Docker daemon are required only for the legacy Compose stack.

```bash
nix run .#compose -- up
```

The wrapper uses the pinned Vexa source as the Compose build context. To run a local Vexa checkout instead:

```bash
VEXA_SOURCE=/path/to/vexa nix run .#compose -- up
```

The default Compose mode keeps Vexa's upstream object-store behavior: the internal MinIO service is used with `MINIO_ENDPOINT=minio:9000`. To run the Nix-packaged Garage node in the same Compose lifecycle, opt into Garage mode:

```bash
VEXA_OBJECT_STORE=garage nix run .#compose -- up
```

In Garage mode the wrapper loads the Garage image built from `garage-nix`, starts a single-node Garage server with its default S3 access key and `vexa-recordings` bucket, waits for `garage status` to become healthy, and only then starts `meeting-api`. The wrapper injects `MINIO_ENDPOINT=garage:3900`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `MINIO_BUCKET=vexa-recordings`, and `MINIO_SECURE=false` into Vexa. Override `GARAGE_ACCESS_KEY`, `GARAGE_SECRET_KEY`, `RECORDING_BUCKET`, `GARAGE_ENDPOINT`, or `GARAGE_SECURE` when needed; the standard `MINIO_*` defaults are not used to configure Garage.

Copy the upstream environment template before configuring services:

```bash
cp "$(nix build .#vexa-source --no-link --print-out-paths)/share/vexa/deploy/compose/.env.example" .env

# The wrapper forwards this file into the temporary Compose tree.
```

## Development shell

```bash
nix develop
```

This provides Node.js 22, pnpm, the Docker and Docker Compose CLIs, pytest with pytest-asyncio, the Nix-resolved Python 3.12 runtime environment, uv, and the update tooling. `VEXA_SOURCE` points at the pinned source tree inside the shell. The Docker daemon remains an external host service; the flake supplies the client tools needed for the Compose-managed browser workloads.

The runtime service is also available as a standalone Nix package. Its environment is generated from Vexa's `core/runtime/uv.lock` plus the production-only `uvicorn[standard]==0.34.0` dependency declared by the upstream Dockerfile:

```bash
nix build .#vexa-runtime-env
nix build .#vexa-runtime
```

To run the runtime service directly, use the Nix-native process backend. It does not require Docker or a Docker socket:

```bash
nix run .#runtime
```

The process backend launches workloads as isolated child process groups. Set `REDIS_URL` to enable scheduling and configure the workload command/profile environment expected by the selected Vexa flow.

The local PostgreSQL and Valkey infrastructure can also run without Docker:

```bash
nix run .#infra
```

By default it stores state under `$XDG_STATE_HOME/vexa` (or `$HOME/.local/state/vexa`), listens on PostgreSQL `5432` and Valkey `6379`, and creates the `vexa` database. Override `VEXA_INFRA_STATE_DIR`, `POSTGRES_PORT`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, or `VALKEY_PORT` as needed. MinIO is intentionally not bundled because the current nixpkgs package is marked insecure and abandoned; configure an external S3-compatible endpoint for recording storage.

For recording storage outside Compose, export `S3_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, and `RECORDING_BUCKET` before starting `meeting-api`. A small self-hosted Garage deployment is the recommended external S3-compatible backend for this project; AWS S3, Cloudflare R2, Backblaze B2, or another compatible service work as well. The `vexa-infra` app does not start or own an object-store data directory. The Compose wrapper's opt-in Garage mode above is the exception: it owns a local single-node Garage data directory through Compose volumes and wires that node into `meeting-api`.

Authenticated browser profiles use a separate scoped store: set `BOT_USERDATA_S3_PATH`, `BOT_S3_ENDPOINT`, `BOT_S3_BUCKET`, `BOT_S3_ACCESS_KEY`, and `BOT_S3_SECRET_KEY`. The hybrid bot launcher forwards the `BOT_S3_*` settings into the Docker bot; credentials should be scoped to the relevant bucket/prefix rather than shared administrator credentials.

For example, with an external S3-compatible service:

```bash
export S3_ENDPOINT=https://s3.example.invalid
export S3_ACCESS_KEY=recording-access
export S3_SECRET_KEY=recording-secret
export RECORDING_BUCKET=vexa-recordings
export BOT_USERDATA_S3_PATH=userdata/default
export BOT_S3_ENDPOINT="$S3_ENDPOINT"
export BOT_S3_BUCKET=vexa-userdata
export BOT_S3_ACCESS_KEY=bot-userdata-access
export BOT_S3_SECRET_KEY=bot-userdata-secret
```

For a local development Garage node, keep its data outside the Nix store and run it as a separate process. The flake gets Garage `2.3.0` from the standalone [garage-nix](https://github.com/kuro1981/garage-nix) package, including the single-node bootstrap flags. Run the following commands inside `nix develop` (or after direnv has loaded the flake):

```bash
garage_state="${XDG_STATE_HOME:-$HOME/.local/state}/vexa/garage"
mkdir -p "$garage_state/meta" "$garage_state/data"
cat > "$garage_state/garage.toml" <<EOF
metadata_dir = "$garage_state/meta"
data_dir = "$garage_state/data"
db_engine = "sqlite"
replication_factor = 1
rpc_bind_addr = "127.0.0.1:3901"
rpc_public_addr = "127.0.0.1:3901"
rpc_secret = "$(openssl rand -hex 32)"

[s3_api]
api_bind_addr = "127.0.0.1:3900"
s3_region = "garage"
EOF

export GARAGE_CONFIG_FILE="$garage_state/garage.toml"
export GARAGE_DEFAULT_ACCESS_KEY="GK$(openssl rand -hex 16)"
export GARAGE_DEFAULT_SECRET_KEY="$(openssl rand -hex 32)"
export GARAGE_DEFAULT_BUCKET=vexa-recordings
garage server --single-node --default-bucket
```

Keep the generated access key and secret key in the shell that starts Vexa, then point the Nix services at the local Garage endpoint:

```bash
export S3_ENDPOINT=http://127.0.0.1:3900
export S3_ACCESS_KEY="$GARAGE_DEFAULT_ACCESS_KEY"
export S3_SECRET_KEY="$GARAGE_DEFAULT_SECRET_KEY"
export RECORDING_BUCKET=vexa-recordings
```

This single-node setup is for development only and has no redundancy. For production, use a multi-node Garage deployment or a managed S3 service with backups and TLS.

The small auxiliary lock workspace under `nix/uvicorn/` keeps the Dockerfile-only dependency pinned without modifying the fetched Vexa source.

The gateway production environment is available separately because its upstream Dockerfile intentionally overrides Redis and uvicorn versions:

```bash
nix build .#vexa-gateway-env
INTERNAL_API_SECRET=vexa-internal-secret nix run .#gateway
```

The gateway fails closed unless `INTERNAL_API_SECRET` is set. Its other service URLs and Redis URL use the upstream defaults unless explicitly overridden.

The meeting API has its own production environment because the upstream image adds the ASGI server, async PostgreSQL stack, and S3 client outside its service lockfile:

```bash
nix build .#vexa-meeting-api-env
INTERNAL_API_SECRET=vexa-internal-secret ADMIN_TOKEN=changeme nix run .#meeting-api
```

The service starts its HTTP process before attempting its background Postgres and Redis loops, so those backing services must be available for a functional deployment.

The remaining Python Compose services are also available as independent Nix apps. Admin-api adds the async PostgreSQL stack from its Dockerfile, agent-api uses only the upstream `control-plane` dependency group, and MCP combines its service lockfile with the Dockerfile's ASGI server:

```bash
nix build .#vexa-admin-api-env
nix build .#vexa-agent-api-env
nix build .#vexa-mcp-env

DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost:5432/vexa nix run .#admin-api
nix run .#agent-api
GATEWAY_URL=http://localhost:18000 nix run .#mcp
```

Admin-api requires the Compose database configuration, agent-api requires the control-plane service configuration, and MCP requires a reachable gateway. The service environments remain separate so each upstream lockfile and production override keeps its own version resolution.

The agent worker is also available directly for the process backend. It uses the upstream worker dependencies plus Numtide's `llm-agents.nix` `claude-code` package, and receives its dispatch through the same environment contract as the upstream `AGENT_WORKER_COMMAND` launcher:

```bash
nix build .#vexa-agent-worker-env
nix run .#agent-worker
```

The standalone worker expects a runtime dispatch environment and Claude credentials. The runtime app wires this worker automatically when `RUNTIME_BACKEND=process`; no Docker image or Docker socket is involved.

### Nix/Docker boundary

The recommended boundary is deliberately hybrid:

- Nix owns the pinned Vexa source, Python environments, API services, terminal, process runtime, PostgreSQL, and Valkey. These are stable inputs that benefit from reproducible derivations.
- Docker owns ephemeral meeting workloads when their environment is intentionally mutable or host-like: the browser bot, Playwright/Chromium, Xvfb, PulseAudio, browser profiles, model caches, and mounted user workspaces.

The browser bot is therefore launched through Docker from the Nix process runtime. `nix run .#runtime` sets `RUNTIME_BACKEND=process`, points `BOT_COMMAND` at the generated Docker launcher, and keeps the agent worker in its Nix environment. The Docker daemon remains external, while `BROWSER_IMAGE` and `VEXA_DOCKER_NETWORK` can override the bot image and network:

```bash
BROWSER_IMAGE=vexaai/vexa-bot:v012 \
VEXA_DOCKER_NETWORK=host \
nix run .#runtime
```

The launcher is also exposed for a direct smoke or operational call as `nix run .#bot-docker-launcher`. The legacy Compose app remains available when the entire Vexa stack should run in Docker rather than using the hybrid boundary.

The terminal is built from its self-contained npm lockfile with Nix's Node builder. It runs the same custom Next.js server as Compose and defaults to production mode:

```bash
nix build .#vexa-terminal
GATEWAY_URL=http://localhost:18056 \
AGENT_API_URL=http://localhost:18100 \
VEXA_ADMIN_API_URL=http://localhost:18057 \
NEXTAUTH_SECRET=vexa-dev-secret \
nix run .#terminal
```

The terminal needs the gateway, agent-api, and admin-api endpoints to provide a functional UI. Its npm dependency hash is kept in [flake.nix](flake.nix), while the fetched Vexa source remains the single source of the application code.

## Update

Check whether `main` moved:

```bash
nix develop --command bash scripts/update.sh --check
```

Update the commit, source hash, flake lock, and source build verification:

```bash
nix develop --command bash scripts/update.sh
```

An explicit commit can be selected for a reproducible release candidate:

```bash
nix develop --command bash scripts/update.sh --rev <commit>
```

The same update is checked daily by GitHub Actions and submitted as a pull request.

## Verification status

The following checks have passed for the current pinned Vexa source and flake:

- `nix flake check --all-systems`
- Runtime tests: `158 passed, 2 skipped`
- Garage `2.3.0` single-node startup from the standalone [garage-nix](https://github.com/kuro1981/garage-nix) flake
- Authenticated Garage S3 `put`, `list`, and `get` using AWS CLI v2
- Nix-managed PostgreSQL and Valkey startup with a temporary state directory
- Docker CLI `29.6.2` and Compose `5.3.1` through the devShell
- `vexaai/vexa-bot:v012` image pull and Nix-generated bot launcher startup
- Browser container initialization: Xvfb, fluxbox, PulseAudio, Chromium, and Node bot worker
- Public Jitsi connection and lobby arrival from the browser bot

In environments without a Docker daemon, the launcher can use a Podman Docker-compatible API by exporting `DOCKER_HOST`. The browser bot reached the Jitsi lobby and performed a graceful leave, but a moderator was not available to admit it into the conference. The direct launcher smoke therefore does not replace a full meeting API end-to-end test.

The remaining end-to-end checks are:

- Start gateway and meeting-api together with PostgreSQL, Valkey, and Garage.
- Create a meeting through the meeting API instead of invoking the bot directly.
- Admit the bot to a Jitsi meeting or use a self-hosted room without lobby admission.
- Verify recording, transcript, lifecycle callback, and browser userdata persistence.
- Configure multi-node Garage, TLS, backups, and production-scoped credentials before production use.

## Verification

```bash
nix flake check
nix build .#vexa-source
```
