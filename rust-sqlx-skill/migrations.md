# SQLx Migrations

## Setup

### Install sqlx-cli
```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
```

### Environment setup
Create a `.env` file with your database URL:
```
DATABASE_URL=postgres://user:password@localhost:5432/myapp
```

### Initialize migrations directory
```bash
sqlx database create
sqlx migrate add initial_schema
```

This creates `migrations/` directory with timestamped files.

## Migration Structure

### Reversible migrations (recommended)
Each migration creates two files:
- `{timestamp}_{name}.up.sql` - forward migration
- `{timestamp}_{name}.down.sql` - rollback migration

```bash
sqlx migrate add -r create_users_table
```

Creates:
```
migrations/
  20240115120000_create_users_table.up.sql
  20240115120000_create_users_table.down.sql
```

### Simple migrations (one-way)
```bash
sqlx migrate add create_users_table
```

Creates single file `migrations/20240115120000_create_users_table.sql`.

## Writing Migrations

### Example: Create users table

**up.sql:**
```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255),
    password_hash VARCHAR(255) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    metadata JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_active ON users(active) WHERE active = true;
```

**down.sql:**
```sql
DROP TABLE IF EXISTS users;
```

### Example: Add column

**up.sql:**
```sql
ALTER TABLE users ADD COLUMN last_login_at TIMESTAMPTZ;
```

**down.sql:**
```sql
ALTER TABLE users DROP COLUMN IF EXISTS last_login_at;
```

### Example: Add foreign key

**up.sql:**
```sql
CREATE TABLE posts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_published ON posts(published_at) WHERE published_at IS NOT NULL;
```

**down.sql:**
```sql
DROP TABLE IF EXISTS posts;
```

### Example: Data migration

**up.sql:**
```sql
-- Add new column
ALTER TABLE users ADD COLUMN email_verified BOOLEAN;

-- Migrate existing data
UPDATE users SET email_verified = true WHERE created_at < '2024-01-01';
UPDATE users SET email_verified = false WHERE email_verified IS NULL;

-- Make column NOT NULL after data migration
ALTER TABLE users ALTER COLUMN email_verified SET NOT NULL;
ALTER TABLE users ALTER COLUMN email_verified SET DEFAULT false;
```

**down.sql:**
```sql
ALTER TABLE users DROP COLUMN IF EXISTS email_verified;
```

## Running Migrations

### Apply all pending migrations
```bash
sqlx migrate run
```

### Rollback last migration
```bash
sqlx migrate revert
```

### Check migration status
```bash
sqlx migrate info
```

### Run migrations programmatically
```rust
use sqlx::PgPool;
use sqlx::migrate::MigrateDatabase;

pub async fn run_migrations(pool: &PgPool) -> Result<(), sqlx::Error> {
    sqlx::migrate!("./migrations")
        .run(pool)
        .await?;
    Ok(())
}
```

Embed migrations in binary:
```rust
pub async fn setup_database(database_url: &str) -> Result<PgPool, sqlx::Error> {
    if !sqlx::Postgres::database_exists(database_url).await? {
        sqlx::Postgres::create_database(database_url).await?;
    }

    let pool = PgPool::connect(database_url).await?;
    sqlx::migrate!().run(&pool).await?;
    Ok(pool)
}
```

## Best Practices

### 1. Keep migrations atomic
Each migration should do one thing. Easier to debug and rollback.

```bash
# Good: separate migrations
sqlx migrate add create_users_table
sqlx migrate add create_posts_table
sqlx migrate add add_user_avatar_column

# Avoid: everything in one migration
sqlx migrate add initial_schema_with_everything
```

### 2. Never modify deployed migrations
Once a migration has run in production, treat it as immutable. Create a new migration for changes.

### 3. Use transactions (PostgreSQL DDL is transactional)
```sql
BEGIN;

CREATE TABLE users (...);
CREATE INDEX ...;
INSERT INTO ...;

COMMIT;
```

### 4. Handle nullable transitions carefully
```sql
-- Step 1: Add nullable column
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- Step 2: Backfill data (separate migration or script)
UPDATE users SET phone = 'unknown' WHERE phone IS NULL;

-- Step 3: Make NOT NULL (separate migration after backfill verified)
ALTER TABLE users ALTER COLUMN phone SET NOT NULL;
```

### 5. Index concurrently for large tables
```sql
CREATE INDEX CONCURRENTLY idx_users_email ON users(email);
```

Note: `CONCURRENTLY` cannot run inside a transaction block.

### 6. Add meaningful constraints
```sql
ALTER TABLE users ADD CONSTRAINT chk_users_email_format
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
```

## Troubleshooting

### Migration checksum mismatch
If you accidentally modified a migration file:
```bash
# See which migration has wrong checksum
sqlx migrate info

# Fix: restore original file content, or for development only:
# DELETE FROM _sqlx_migrations WHERE version = {timestamp};
```

### Database doesn't exist
```bash
sqlx database create
```

### Reset database (development only)
```bash
sqlx database drop
sqlx database create
sqlx migrate run
```
