# SQLx Coding Patterns and Style

## Struct Conventions

Following project Rust policy: all fields public, structs public, methods public.

### Database entity structs
```rust
use chrono::{DateTime, Utc};
use sqlx::FromRow;

#[derive(Debug, Clone, FromRow)]
pub struct User {
    pub id: i64,
    pub email: String,
    pub name: Option<String>,
    pub active: bool,
    pub status: UserStatus,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}
```

### Database enums
Enums stored as TEXT in Postgres with snake_case serialization:

```rust
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema, sqlx::Type)]
#[sqlx(type_name = "TEXT")]
#[sqlx(rename_all = "snake_case")]
#[serde(rename_all = "snake_case")]
pub enum UserStatus {
    Pending,
    Active,
    Suspended,
    Deleted,
}

impl std::fmt::Display for UserStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let s = match self {
            UserStatus::Pending => "pending",
            UserStatus::Active => "active",
            UserStatus::Suspended => "suspended",
            UserStatus::Deleted => "deleted",
        };
        write!(f, "{s}")
    }
}
```

Key attributes:
- `sqlx::Type` - enables sqlx to encode/decode the enum
- `#[sqlx(type_name = "TEXT")]` - stores as TEXT column in Postgres
- `#[sqlx(rename_all = "snake_case")]` - database values use snake_case
- `#[serde(rename_all = "snake_case")]` - JSON serialization matches database
- `Display` impl - for logging and string conversion

### Manual sqlx trait implementations for custom types
When you need full control over encoding/decoding (custom parsing, default values, etc.):

```rust
use serde::{Deserialize, Serialize};
use sqlx::postgres::{PgArgumentBuffer, PgTypeInfo, PgValueRef};
use sqlx::{Decode, Encode, Postgres};
use std::error::Error;
use std::fmt::Display;

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub enum UserRole {
    User,
    Admin,
}

impl Display for UserRole {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UserRole::User => write!(f, "user"),
            UserRole::Admin => write!(f, "admin"),
        }
    }
}

impl From<String> for UserRole {
    fn from(s: String) -> Self {
        match s.as_str() {
            "user" => UserRole::User,
            "admin" => UserRole::Admin,
            _ => UserRole::User,
        }
    }
}

impl From<Option<String>> for UserRole {
    fn from(s: Option<String>) -> Self {
        match s {
            Some(s) => UserRole::from(s),
            None => UserRole::User,
        }
    }
}

impl sqlx::Type<Postgres> for UserRole {
    fn type_info() -> PgTypeInfo {
        <String as sqlx::Type<Postgres>>::type_info()
    }
}

impl Encode<'_, Postgres> for UserRole {
    fn encode_by_ref(
        &self,
        buf: &mut PgArgumentBuffer,
    ) -> Result<sqlx::encode::IsNull, Box<dyn Error + 'static + Send + Sync>> {
        <String as Encode<Postgres>>::encode(self.to_string(), buf)
    }
}

impl Decode<'_, Postgres> for UserRole {
    fn decode(
        value: PgValueRef<'_>,
    ) -> Result<Self, Box<dyn Error + 'static + Send + Sync>> {
        let value = <&str as Decode<Postgres>>::decode(value)?;
        Ok(Self::from(value.to_string()))
    }
}
```

When to use manual implementations:
- Custom default values for unknown/invalid database values
- Complex parsing logic beyond simple string mapping
- Wrapper types around primitives (e.g., `UserId(i64)`)
- Types that need validation during decode
- Interop with external crates that don't support sqlx derives

### Input structs for queries
Use input structs when:
- More than one argument of the same type
- More than three arguments total
- Parameters represent a logical unit

```rust
pub struct CreateUserInput {
    pub email: String,
    pub name: Option<String>,
    pub password_hash: String,
}

pub struct UpdateUserInput {
    pub id: i64,
    pub name: Option<String>,
    pub active: Option<bool>,
}

pub struct UserSearchInput {
    pub email: Option<String>,
    pub name: Option<String>,
    pub active: Option<bool>,
    pub limit: i64,
    pub offset: i64,
}
```

### Always destructure input structs
Ensures all fields are used, catches dead code at compile time:

```rust
use sqlx::{Postgres, Transaction};

impl User {
    pub async fn create(
        transaction: &mut Transaction<'_, Postgres>,
        input: CreateUserInput,
    ) -> anyhow::Result<Self> {
        let CreateUserInput {
            email,
            name,
            password_hash,
        } = input;

        sqlx::query_as!(
            Self,
            r#"
            INSERT INTO users (email, name, password_hash)
            VALUES ($1, $2, $3)
            RETURNING id, email, name, active, created_at, updated_at
            "#,
            email,
            name,
            password_hash
        )
        .fetch_one(&mut **transaction)
        .await
    }

    pub async fn search(
        transaction: &mut Transaction<'_, Postgres>,
        input: UserSearchInput,
    ) -> anyhow::Result<Vec<Self>> {
        let UserSearchInput {
            email,
            name,
            active,
            limit,
            offset,
        } = input;

        sqlx::query_as!(
            Self,
            r#"
            SELECT id, email, name, active, created_at, updated_at
            FROM users
            WHERE ($1::text IS NULL OR email ILIKE '%' || $1 || '%')
              AND ($2::text IS NULL OR name ILIKE '%' || $2 || '%')
              AND ($3::bool IS NULL OR active = $3)
            ORDER BY created_at DESC
            LIMIT $4 OFFSET $5
            "#,
            email,
            name,
            active,
            limit,
            offset
        )
        .fetch_all(&mut **transaction)
        .await
    }
}
```

## Static Methods on Entity Structs

Organize database operations as static methods on the entity struct itself:

```rust
// src/db/mod.rs
pub mod users;
pub mod posts;

pub use users::User;
pub use posts::Post;
```

```rust
// src/db/users.rs
use sqlx::{Postgres, Transaction};

impl User {
    pub async fn find_by_id(
        transaction: &mut Transaction<'_, Postgres>,
        id: i64,
    ) -> anyhow::Result<Option<Self>> {
        sqlx::query_as!(Self, "SELECT * FROM users WHERE id = $1", id)
            .fetch_optional(&mut **transaction)
            .await
    }

    pub async fn find_by_email(
        transaction: &mut Transaction<'_, Postgres>,
        email: &str,
    ) -> anyhow::Result<Option<Self>> {
        sqlx::query_as!(Self, "SELECT * FROM users WHERE email = $1", email)
            .fetch_optional(&mut **transaction)
            .await
    }

    pub async fn create(
        transaction: &mut Transaction<'_, Postgres>,
        input: CreateUserInput,
    ) -> anyhow::Result<Self> {
        let CreateUserInput { email, name, password_hash } = input;

        sqlx::query_as!(
            Self,
            "INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING *",
            email,
            name,
            password_hash
        )
        .fetch_one(&mut **transaction)
        .await
    }

    pub async fn update(
        transaction: &mut Transaction<'_, Postgres>,
        input: UpdateUserInput,
    ) -> anyhow::Result<Self> {
        let UpdateUserInput { id, name, active } = input;

        sqlx::query_as!(
            Self,
            r#"
            UPDATE users
            SET name = COALESCE($2, name),
                active = COALESCE($3, active),
                updated_at = NOW()
            WHERE id = $1
            RETURNING *
            "#,
            id,
            name,
            active
        )
        .fetch_one(&mut **transaction)
        .await
    }

    pub async fn delete(
        transaction: &mut Transaction<'_, Postgres>,
        id: i64,
    ) -> anyhow::Result<bool> {
        let result = sqlx::query!("DELETE FROM users WHERE id = $1", id)
            .execute(&mut **transaction)
            .await?;

        Ok(result.rows_affected() > 0)
    }
}
```

## Error Handling

Use `anyhow::Result<T>` for all database operations for consistent error handling and easy context addition:

```rust
use anyhow::{Context, Result};

impl User {
    pub async fn find_by_id(
        transaction: &mut Transaction<'_, Postgres>,
        id: i64,
    ) -> Result<Option<Self>> {
        sqlx::query_as!(Self, "SELECT * FROM users WHERE id = $1", id)
            .fetch_optional(&mut **transaction)
            .await
            .context("failed to fetch user by id")
    }

    pub async fn create(
        transaction: &mut Transaction<'_, Postgres>,
        input: CreateUserInput,
    ) -> Result<Self> {
        let CreateUserInput { email, name, password_hash } = input;

        sqlx::query_as!(
            Self,
            "INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING *",
            email,
            name,
            password_hash
        )
        .fetch_one(&mut **transaction)
        .await
        .with_context(|| format!("failed to create user with email: {}", email))
    }
}
```

Key patterns:
- `.context("message")` - adds static context to errors
- `.with_context(|| format!(...))` - adds dynamic context (lazy evaluation)
- `?` operator propagates errors with full context chain
- `anyhow::bail!("message")` - early return with error

## Connection Pool Setup

```rust
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use std::time::Duration;

pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub min_connections: u32,
    pub acquire_timeout_secs: u64,
    pub idle_timeout_secs: u64,
}

pub async fn create_pool(config: DatabaseConfig) -> anyhow::Result<PgPool> {
    let DatabaseConfig {
        url,
        max_connections,
        min_connections,
        acquire_timeout_secs,
        idle_timeout_secs,
    } = config;

    PgPoolOptions::new()
        .max_connections(max_connections)
        .min_connections(min_connections)
        .acquire_timeout(Duration::from_secs(acquire_timeout_secs))
        .idle_timeout(Duration::from_secs(idle_timeout_secs))
        .connect(&url)
        .await
}
```

## Testing Patterns

### Test database setup with transactions
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::PgPool;

    async fn setup_test_db() -> PgPool {
        let url = std::env::var("TEST_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/test".to_string());

        let pool = PgPool::connect(&url).await.unwrap();
        sqlx::migrate!().run(&pool).await.unwrap();
        pool
    }

    #[tokio::test]
    async fn test_create_user() {
        let pool = setup_test_db().await;
        let mut tx = pool.begin().await.unwrap();

        let input = CreateUserInput {
            email: "test@example.com".to_string(),
            name: Some("Test User".to_string()),
            password_hash: "hash".to_string(),
        };

        let user = User::create(&mut tx, input).await.unwrap();

        assert_eq!(user.email, "test@example.com");
        assert_eq!(user.name, Some("Test User".to_string()));

        tx.rollback().await.unwrap();
    }
}
```

### Using #[sqlx::test] for automatic rollback
```rust
#[cfg(test)]
mod tests {
    use sqlx::PgPool;

    #[sqlx::test]
    async fn test_with_auto_rollback(pool: PgPool) {
        let mut tx = pool.begin().await.unwrap();

        let input = CreateUserInput {
            email: "test@example.com".to_string(),
            name: None,
            password_hash: "hash".to_string(),
        };

        let user = User::create(&mut tx, input).await.unwrap();
        assert!(user.id > 0);

        // Transaction rolls back when test ends
    }
}
```

## Query Organization

### Separate query files (optional)
For complex queries, consider separate SQL files:

```
src/
  db/
    users/
      mod.rs
      queries/
        find_active_with_posts.sql
        search_with_stats.sql
```

Load with `include_str!`:
```rust
const FIND_ACTIVE_WITH_POSTS: &str = include_str!("queries/find_active_with_posts.sql");

impl UserWithPosts {
    pub async fn find_active(
        transaction: &mut Transaction<'_, Postgres>,
    ) -> anyhow::Result<Vec<Self>> {
        sqlx::query_as(FIND_ACTIVE_WITH_POSTS)
            .fetch_all(&mut **transaction)
            .await
    }
}
```

Note: This uses runtime queries. For compile-time checking, inline the SQL in `query_as!`.

## Common Patterns

### Soft deletes
```rust
pub struct User {
    pub id: i64,
    pub email: String,
    pub deleted_at: Option<DateTime<Utc>>,
}

impl User {
    pub async fn soft_delete(
        transaction: &mut Transaction<'_, Postgres>,
        id: i64,
    ) -> anyhow::Result<()> {
        sqlx::query!("UPDATE users SET deleted_at = NOW() WHERE id = $1", id)
            .execute(&mut **transaction)
            .await?;
        Ok(())
    }

    pub async fn find_active(
        transaction: &mut Transaction<'_, Postgres>,
    ) -> anyhow::Result<Vec<Self>> {
        sqlx::query_as!(Self, "SELECT * FROM users WHERE deleted_at IS NULL")
            .fetch_all(&mut **transaction)
            .await
    }
}
```

### Pagination
```rust
pub struct PaginationInput {
    pub page: i64,
    pub per_page: i64,
}

pub struct PaginatedResult<T> {
    pub items: Vec<T>,
    pub total: i64,
    pub page: i64,
    pub per_page: i64,
    pub total_pages: i64,
}

impl User {
    pub async fn paginate(
        transaction: &mut Transaction<'_, Postgres>,
        input: PaginationInput,
    ) -> anyhow::Result<PaginatedResult<Self>> {
        let PaginationInput { page, per_page } = input;
        let offset = (page - 1) * per_page;

        let total = sqlx::query_scalar!("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL")
            .fetch_one(&mut **transaction)
            .await?
            .unwrap_or(0);

        let items = sqlx::query_as!(
            Self,
            "SELECT * FROM users WHERE deleted_at IS NULL ORDER BY id LIMIT $1 OFFSET $2",
            per_page,
            offset
        )
        .fetch_all(&mut **transaction)
        .await?;

        Ok(PaginatedResult {
            items,
            total,
            page,
            per_page,
            total_pages: (total as f64 / per_page as f64).ceil() as i64,
        })
    }
}
```

### Upsert (INSERT ON CONFLICT)
```rust
impl User {
    pub async fn upsert(
        transaction: &mut Transaction<'_, Postgres>,
        input: CreateUserInput,
    ) -> anyhow::Result<Self> {
        let CreateUserInput { email, name, password_hash } = input;

        sqlx::query_as!(
            Self,
            r#"
            INSERT INTO users (email, name, password_hash)
            VALUES ($1, $2, $3)
            ON CONFLICT (email) DO UPDATE SET
                name = EXCLUDED.name,
                password_hash = EXCLUDED.password_hash,
                updated_at = NOW()
            RETURNING *
            "#,
            email,
            name,
            password_hash
        )
        .fetch_one(&mut **transaction)
        .await
    }
}
```
