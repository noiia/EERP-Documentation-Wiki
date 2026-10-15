# Getting Started

This guide gets EERP running on your machine and points you at your first change.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Docker + Docker Compose | v2 | the whole dev stack (database, object storage, Redis, NATS, mail catcher, backend, gateway) |
| Go | 1.26 | backend tests and tooling |
| Node.js + pnpm | Node 20+, pnpm via `npx -y pnpm@<version>` works | frontend dev server and tests |
| Make, `openssl` | any | task runner, secret generation |

!!! note "No Rust toolchain needed"
    Module WASM binaries are **Go source cross-compiled to WASI**, and every module shipped today
    is `"type": "go"` (compiled into the core binary), so the WASM build never runs in practice.
    See [Module System](core/module-system.md#module-anatomy).

## 1. Clone and bootstrap

```bash
git clone https://github.com/noiia/EERP.git
cd EERP
make bootstrap
```

`make bootstrap` (`infra/bootstrap.sh`) does everything a fresh checkout needs, idempotently:

- generates missing secrets into the gitignored `.env` (database password, `master_key`, S3 key
  pair, Garage RPC secret);
- creates `eerp-config.json` and `eerp-config.docker.json` from their `*.example.json` templates
  and fills in those secrets;
- starts every service and waits until each is healthy;
- installs `pg_trgm` (PostGIS comes with the database image);
- bootstraps Garage (bucket + access key).

Run it again any time — it only fills what's missing. `ROTATE=1 make bootstrap` regenerates the
secrets in place (data kept). See [Deployment & Bootstrap](developer-guide/deployment.md#use-case-1-local-development).

## 2. Open it

| URL | What |
|---|---|
| `https://localhost/` | the public website (self-signed certificate — accept it once) |
| `https://localhost/app` | the ERP — sign in as **`admin@eerp.local` / `admin`** |
| `http://127.0.0.1:8025` | Mailpit: every email the stack sends |

The dev admin is seeded automatically; with `environment: "development"` it isn't forced to change
its password.

## 3. Day-to-day commands

```bash
make run              # dev stack + backend container + Next.js dev server (hot reload) on :3000
make run-back         # (re)start only the backend container
make run-front-dev    # only the Next.js dev server
make logs             # follow the stack's logs
make test             # every CI check: Go (+ Redis tests), dead code gate, pdf-service, frontend
```

The backend runs in Docker in dev; the frontend dev server runs on the host for fast reloads.
Run a subset of the Go tests with:

```bash
make run-back-tests BACKTESTPATH=./orm/... ARGS="-v -run TestFindOne"
```

See [Testing](developer-guide/testing.md) for the database-backed test rules.

## 4. Fill it with data

Settings → **Developer** seeds fake data: a *light* set through the normal API (a few records of
everything, pictures, a full Event demo), or the *full* volume (~100 000 rows per business table,
run in the background with live progress under the bell). See [Demo Data](core/demo-data.md).

## 5. Make a change

- Scaffold a module: `go run ./tools/eerp-init-module -p core/modules/<name> -t go` — it writes
  `module.json`/`module.go` and the frontend `views/`, wires the module into `core/modules/all`,
  and links it into the frontend workspace. Then follow
  [Building a Module From Scratch](developer-guide/module-from-scratch.md).
- Read [Architecture Overview](architecture/index.md) for how the layers fit, and [ORM](core/orm.md)
  for database access.

## Troubleshooting

| Symptom | Fix |
|---|---|
| backend refuses to boot: `master_key is empty or set to the insecure default` | run `make bootstrap` (it fills the config) |
| browser certificate warning on `https://localhost` | expected in dev (self-signed); accept it |
| tests hang while migrating | a killed `go test` left a Postgres session holding the schema advisory lock: find it with `docker exec db psql -U postgres -d poc -Atc "SELECT pid FROM pg_locks WHERE locktype='advisory'"`, `SELECT pg_terminate_backend(<pid>)`, and always pass `-timeout` |
| no emails arrive | open Mailpit (`127.0.0.1:8025`); dev never sends real mail |
