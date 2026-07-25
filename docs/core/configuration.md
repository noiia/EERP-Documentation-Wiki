# Configuration

EERP uses a single JSON file as its sole configuration source. There is no environment variable inheritance, no multi-file override chains, and no runtime mutation of configuration.

---

## Purpose

Configuration complexity is a common source of deployment bugs. A value set in an environment variable overrides a file, which overrides a default, and the effective configuration becomes hard to reason about. EERP's approach: one file, one source of truth, validated at startup.

---

## Configuration File

The file path is passed via the `-config` CLI flag:

```bash
go run ./cmd/app/... -config="../../eerp-config.json"
```

### Full Reference

```json
{
    "module_root": ["/absolute/path/to/modules"],
    "master_key": "change-me-in-production",
    "db_name": "poc",
    "db_port": 5432,
    "db_host": "localhost",
    "db_user": "postgres",
    "db_password": "postgres",
    "max_connection": 10,
    "min_connection": 4,
    "max_conn_idle_time": 1800,
    "max_conn_life_time": 3600,
    "health_check_period": 60,
    "connect_timeout": 10,
    "allowed_origins": ["https://app.example.com"],
    "request_body_limit": "1M",
    "auth_rate_limit_per_minute": 20
}
```

### Field Reference

| Field | Type | Description |
|---|---|---|
| `module_root` | `[]string` | Absolute paths to directories the module loader scans for `module.json` files |
| `master_key` | string | Signing key for tokens and encrypted fields; **never commit to version control** |
| `db_name` | string | PostgreSQL database name |
| `db_port` | int | PostgreSQL port |
| `db_host` | string | PostgreSQL host |
| `db_user` | string | PostgreSQL user |
| `db_password` | string | PostgreSQL password |
| `max_connection` | int | Maximum pool connections (maps to `orm.Config.MaxConns`) |
| `min_connection` | int | Minimum idle pool connections (maps to `orm.Config.MinConns`) |
| `max_conn_idle_time` | int (seconds) | Close connections idle longer than this |
| `max_conn_life_time` | int (seconds) | Recycle connections older than this |
| `health_check_period` | int (seconds) | How often to ping idle connections |
| `connect_timeout` | int (seconds) | Per-connection establishment timeout |
| `allowed_origins` | `[]string` | CORS allow-list for browser clients. **Empty falls back to `*` (dev only)** — set the frontend origin(s) in production |
| `request_body_limit` | string | Max request body size, e.g. `"1M"`, `"512K"`. Defaults to `"1M"` |
| `auth_rate_limit_per_minute` | int | Per-IP request cap on the `/api/v1/auth/*` endpoints. Defaults to `20` |
| `s3_endpoint` | string | S3-compatible endpoint URL for picture/signature storage. Optional — see [Object Storage](object-storage.md) |
| `s3_region` | string | Region string sent to the S3 client. Optional |
| `s3_bucket` | string | Bucket for picture/signature objects. Optional |
| `s3_access_key` | string | S3 access key. Optional |
| `s3_secret_key` | string | S3 secret key. Optional |

!!! note "Object storage is all-or-nothing"
    The `/api/v1/pictures` routes only mount when **both** `s3_endpoint` and `s3_bucket` are set. Leaving all five `s3_*` fields empty is a valid configuration — picture/signature widgets are simply unavailable, not broken. See [Object Storage](object-storage.md).

!!! note "Security-related fields are optional with safe defaults"
    `request_body_limit` and `auth_rate_limit_per_minute` apply sensible defaults when omitted. `allowed_origins` is the exception: leaving it empty is convenient for local dev but permits any origin — always set it in production. `main.go` logs a warning at startup when it is unset.

---

## Loading Sequence

```mermaid
flowchart TD
    A["-config flag"] --> B["common.DecodeJSON[*types.Config](path)"]
    B --> C{File exists?}
    C -- No --> D["Fatal: config file not found"]
    C -- Yes --> E{Valid JSON?}
    E -- No --> F["Fatal: JSON parse error"]
    E -- Yes --> G["Config struct populated"]
    G --> H["Build DSN from db_* fields"]
    G --> I["Build orm.Config from connection fields"]
    H & I --> J["orm.Open(ormConfig, logger)"]
    G --> K["module.LoadModules(config, db)"]
```

`core/internal/common/readjson.go` provides the generic decoder:

```go
cfg, err := common.DecodeJSON[*types.Config](configPath)
```

---

## DSN Construction

The DSN passed to `pgxpool` is assembled at startup:

```
postgres://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}
```

This is done in `cmd/app/main.go` before calling `orm.Open`. The DSN is never logged (it contains the password).

---

## Connection Pool Mapping

| Config field | `orm.Config` field | Notes |
|---|---|---|
| `max_connection` | `MaxConns` | |
| `min_connection` | `MinConns` | |
| `max_conn_idle_time` | `MaxConnIdleTime` | seconds → `time.Duration` |
| `max_conn_life_time` | `MaxConnLifeTime` | seconds → `time.Duration` |
| `health_check_period` | `HealthCheckPeriod` | seconds → `time.Duration` |
| `connect_timeout` | `ConnectTimeout` | seconds → `time.Duration` |

---

## Interactions

```mermaid
graph LR
    File["eerp-config.json"] -->|read once at boot| Config["types.Config"]
    Config -->|db_* fields| DSN["DSN string"]
    Config -->|connection fields| ORMCfg["orm.Config"]
    Config -->|module_root| ML["Module Loader"]
    Config -->|master_key| Auth["Auth / Token signing"]
    DSN --> ORMCfg
    ORMCfg -->|orm.Open| DB["orm.DB"]
```

---

## Security Notes

- The `master_key` signs authentication tokens. Rotate it to invalidate all active sessions.
- The `db_password` is only ever in memory and in the config file. It is not logged.
- In production, the config file should be owned by the process user with `0600` permissions.
- Consider using a secrets manager to populate sensitive fields and write the config file to a tmpfs mount at deploy time.
- Set `allowed_origins` to your exact frontend origin(s) in production; the `*` fallback is for local development only.
- `api_config_path` (`api.yaml`) is loaded **fail-closed**: if the path is set but the file is missing or malformed, the app refuses to start rather than silently dropping the API-surface overrides it contains.
- `auth_rate_limit_per_minute` caps auth attempts per IP; lower it for stricter brute-force protection, or front the service with a shared limiter for multi-instance deployments.

---

## Extension Points

The `types.Config` struct is the single place to add new configuration fields. After adding a field:

1. Add it to `core/internal/types/config.go`
2. Add the JSON tag matching the `eerp-config.json` key
3. Read it from the `Config` struct in `main.go` and wire it to the appropriate component
