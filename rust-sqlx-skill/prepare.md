# SQLx Prepare and Offline Mode

## The Problem

Compile-time macros (`query!`, `query_as!`) require a live database connection during `cargo build`. This creates issues for:
- CI/CD pipelines without database access
- Building in Docker without running Postgres
- Distributed builds
- Reproducible builds

## The Solution: sqlx prepare

`sqlx prepare` pre-computes query metadata and stores it in `.sqlx/` directory. When `SQLX_OFFLINE=true`, sqlx uses cached metadata instead of connecting to database.

## Workflow

### 1. During development (database available)
```bash
# Ensure DATABASE_URL is set
export DATABASE_URL=postgres://user:password@localhost:5432/myapp

# Run cargo check to validate all queries
cargo check

# Generate cached query metadata
cargo sqlx prepare
```

This creates `.sqlx/` directory with JSON files for each query.

### 2. Commit the .sqlx directory
```bash
git add .sqlx/
git commit -m "Update sqlx prepared queries"
```

### 3. In CI/builds (no database)
```bash
# Build with offline mode
SQLX_OFFLINE=true cargo build
```

## Commands Reference

### Generate query cache
```bash
# For single crate
cargo sqlx prepare

# For workspace (all crates)
cargo sqlx prepare --workspace

# Check if cache is up-to-date (useful in CI)
cargo sqlx prepare --check
```

### Verify cache in CI
```yaml
# GitHub Actions example
- name: Check sqlx prepare is up to date
  run: cargo sqlx prepare --check
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Project Configuration

### Cargo.toml features
```toml
[dependencies]
sqlx = { version = "0.8", features = ["runtime-tokio", "postgres", "offline"] }
```

The `offline` feature is required for offline mode to work.

### .env file
```
DATABASE_URL=postgres://user:password@localhost:5432/myapp
```

### .gitignore considerations
```gitignore
# Do NOT ignore .sqlx - it must be committed
# .sqlx/

# But do ignore local env
.env
.env.local
```

## What gets generated

The `.sqlx/` directory contains:
```
.sqlx/
  query-{hash}.json   # One file per unique query
```

Each JSON file contains:
- Query string
- Parameter types
- Return column types and nullability
- Database-specific metadata

## Handling workspace projects

For Cargo workspaces with multiple crates using sqlx:

```bash
# Prepare all crates in workspace
cargo sqlx prepare --workspace

# Or prepare specific crate
cargo sqlx prepare -p my-database-crate
```

The `.sqlx/` directory will be created in the workspace root.

## Integration with cargo clippy

```bash
# Run clippy with offline mode
SQLX_OFFLINE=true cargo clippy

# Or combine in script
export SQLX_OFFLINE=true
cargo clippy --all-features
cargo build
```

## Dockerfile Pattern

```dockerfile
# Stage 1: Build with sqlx offline mode
FROM rust:1.75 as builder

WORKDIR /app

# Copy sqlx cache first (for layer caching)
COPY .sqlx/ .sqlx/

# Copy Cargo files
COPY Cargo.toml Cargo.lock ./

# Copy source
COPY src/ src/
COPY migrations/ migrations/

# Build with offline mode
ENV SQLX_OFFLINE=true
RUN cargo build --release

# Stage 2: Runtime
FROM debian:bookworm-slim
COPY --from=builder /app/target/release/myapp /usr/local/bin/
CMD ["myapp"]
```

## Troubleshooting

### Error: "no queries have been cached"
```bash
# Regenerate with database connection
cargo sqlx prepare
```

### Error: "SQLX_OFFLINE not set but no database URL provided"
Either set DATABASE_URL or enable offline mode:
```bash
export SQLX_OFFLINE=true
```

### Error: "query cache is out of date"
Your code has queries not in the cache:
```bash
# Regenerate cache
cargo sqlx prepare

# Or check what's missing
cargo sqlx prepare --check
```

### Queries not being found in cache
Ensure:
1. `offline` feature is enabled in Cargo.toml
2. `.sqlx/` directory is committed and present
3. `SQLX_OFFLINE=true` is set
4. Cache was generated with same sqlx version

### Workspace issues
```bash
# Make sure you're preparing from workspace root
cd /path/to/workspace/root
cargo sqlx prepare --workspace
```

## CI/CD Example (GitHub Actions)

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Install Rust
        uses: dtolnay/rust-action@stable

      - name: Install sqlx-cli
        run: cargo install sqlx-cli --no-default-features --features rustls,postgres

      - name: Check sqlx cache
        run: cargo sqlx prepare --check
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost:5432/test

      - name: Build (offline)
        run: cargo build --release
        env:
          SQLX_OFFLINE: true

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: test
        ports:
          - 5432:5432
```

## Best Practices

1. **Always run `cargo sqlx prepare` after changing queries**
2. **Commit `.sqlx/` with every PR that changes queries**
3. **Add `cargo sqlx prepare --check` to CI** to catch forgotten updates
4. **Use `SQLX_OFFLINE=true` consistently in Dockerfiles and CI**
5. **Keep DATABASE_URL out of version control** (use .env or CI secrets)
