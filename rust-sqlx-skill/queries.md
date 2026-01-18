# SQLx Query Patterns

## Compile-Time Queries

### Basic query! macro
The `query!` macro checks SQL at compile time against your database schema.

```rust
use sqlx::{Postgres, Transaction};

pub struct UserHelpers;

impl UserHelpers {
    pub async fn get_count(
        transaction: &mut Transaction<'_, Postgres>,
    ) -> anyhow::Result<i64> {
        let record = sqlx::query!("SELECT COUNT(*) as count FROM users")
            .fetch_one(&mut **transaction)
            .await?;

        Ok(record.count.unwrap_or(0))
    }
}
```

### query_as! with typed output
Map directly to a struct with `query_as!`:

```rust
pub struct User {
    pub id: i64,
    pub email: String,
    pub name: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl User {
    pub async fn find_by_id(
        transaction: &mut Transaction<'_, Postgres>,
        user_id: i64,
    ) -> anyhow::Result<Option<Self>> {
        sqlx::query_as!(
            Self,
            r#"
            SELECT id, email, name, created_at
            FROM users
            WHERE id = $1
            "#,
            user_id
        )
        .fetch_optional(&mut **transaction)
        .await
    }
}
```

### query_scalar! for single values
When you need just one value:

```rust
impl User {
    pub async fn exists_by_email(
        transaction: &mut Transaction<'_, Postgres>,
        email: &str,
    ) -> anyhow::Result<bool> {
        let exists = sqlx::query_scalar!(
            "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)",
            email
        )
        .fetch_one(&mut **transaction)
        .await?;

        Ok(exists.unwrap_or(false))
    }
}
```

### Type overrides with `as`
Override inferred types when needed:

```rust
pub struct UserStats {
    pub total_users: i64,
    pub active_users: i64,
}

impl UserStats {
    pub async fn fetch(
        transaction: &mut Transaction<'_, Postgres>,
    ) -> anyhow::Result<Self> {
        sqlx::query_as!(
            Self,
            r#"
            SELECT
                COUNT(*) as "total_users!",
                COUNT(*) FILTER (WHERE active) as "active_users!"
            FROM users
            "#
        )
        .fetch_one(&mut **transaction)
        .await
    }
}
```

Type override suffixes:
- `!` - not null (removes Option wrapper)
- `?` - nullable (adds Option wrapper)
- `: Type` - explicit type cast, e.g., `"count: i64"`

### Postgres arrays
```rust
impl User {
    pub async fn find_by_ids(
        transaction: &mut Transaction<'_, Postgres>,
        ids: &[i64],
    ) -> anyhow::Result<Vec<Self>> {
        sqlx::query_as!(
            Self,
            "SELECT id, email, name, created_at FROM users WHERE id = ANY($1)",
            ids
        )
        .fetch_all(&mut **transaction)
        .await
    }
}
```

### JSONB columns
```rust
use serde::{Deserialize, Serialize};
use sqlx::types::Json;

#[derive(Serialize, Deserialize)]
pub struct UserMetadata {
    pub preferences: Vec<String>,
    pub settings: std::collections::HashMap<String, String>,
}

pub struct UserWithMeta {
    pub id: i64,
    pub email: String,
    pub metadata: Json<UserMetadata>,
}

impl UserWithMeta {
    pub async fn find_by_id(
        transaction: &mut Transaction<'_, Postgres>,
        user_id: i64,
    ) -> anyhow::Result<Option<Self>> {
        sqlx::query_as!(
            Self,
            r#"
            SELECT id, email, metadata as "metadata: Json<UserMetadata>"
            FROM users
            WHERE id = $1
            "#,
            user_id
        )
        .fetch_optional(&mut **transaction)
        .await
    }
}
```

## Runtime Queries

### When to use runtime queries
- Dynamic table/column names
- Optional WHERE clauses
- User-controlled sorting
- Schema not known at compile time

### Basic runtime query with FromRow
```rust
use sqlx::FromRow;

#[derive(FromRow)]
pub struct User {
    pub id: i64,
    pub email: String,
    pub name: Option<String>,
}

impl User {
    pub async fn find_by_email(
        transaction: &mut Transaction<'_, Postgres>,
        email: &str,
    ) -> anyhow::Result<Option<Self>> {
        sqlx::query_as::<_, Self>("SELECT id, email, name FROM users WHERE email = $1")
            .bind(email)
            .fetch_optional(&mut **transaction)
            .await
    }
}
```

### Dynamic queries with QueryBuilder
```rust
use sqlx::QueryBuilder;

pub struct UserFilter {
    pub email: Option<String>,
    pub name: Option<String>,
    pub active: Option<bool>,
}

impl User {
    pub async fn search(
        transaction: &mut Transaction<'_, Postgres>,
        filter: UserFilter,
    ) -> anyhow::Result<Vec<Self>> {
        let UserFilter { email, name, active } = filter;

        let mut builder: QueryBuilder<sqlx::Postgres> =
            QueryBuilder::new("SELECT id, email, name FROM users WHERE 1=1");

        if let Some(email) = email {
            builder.push(" AND email ILIKE ");
            builder.push_bind(format!("%{}%", email));
        }

        if let Some(name) = name {
            builder.push(" AND name ILIKE ");
            builder.push_bind(format!("%{}%", name));
        }

        if let Some(active) = active {
            builder.push(" AND active = ");
            builder.push_bind(active);
        }

        builder
            .build_query_as::<Self>()
            .fetch_all(&mut **transaction)
            .await
    }
}
```

### Bulk inserts with QueryBuilder
```rust
pub struct NewUser {
    pub email: String,
    pub name: Option<String>,
}

impl User {
    pub async fn insert_bulk(
        transaction: &mut Transaction<'_, Postgres>,
        users: Vec<NewUser>,
    ) -> anyhow::Result<()> {
        if users.is_empty() {
            return Ok(());
        }

        let mut builder: QueryBuilder<sqlx::Postgres> =
            QueryBuilder::new("INSERT INTO users (email, name) ");

        builder.push_values(users, |mut b, user| {
            b.push_bind(user.email);
            b.push_bind(user.name);
        });

        builder.build().execute(&mut **transaction).await?;
        Ok(())
    }
}
```

## Fetch Methods

| Method | Returns | Use when |
|--------|---------|----------|
| `fetch_one` | Single row | Exactly one row expected (errors if 0 or >1) |
| `fetch_optional` | `Option<Row>` | Zero or one row expected |
| `fetch_all` | `Vec<Row>` | Multiple rows, load all into memory |
| `fetch` | `Stream<Row>` | Large result sets, process row by row |

### Streaming large results
```rust
use futures::TryStreamExt;
use sqlx::PgPool;

impl User {
    pub async fn process_all(pool: &PgPool) -> anyhow::Result<()> {
        let mut stream = sqlx::query_as!(Self, "SELECT id, email, name, created_at FROM users")
            .fetch(pool);

        while let Some(user) = stream.try_next().await? {
            println!("Processing user: {}", user.email);
        }

        Ok(())
    }
}
```

Note: Streaming requires a connection/pool reference, not a transaction, since the stream borrows the connection for its entire lifetime.

## Transactions

### Starting a transaction
Transactions are created from a pool and passed to methods:

```rust
use sqlx::PgPool;

pub async fn example_service(pool: &PgPool) -> anyhow::Result<()> {
    let mut tx = pool.begin().await?;

    // Pass &mut tx to methods
    User::create(&mut tx, input).await?;
    Profile::create(&mut tx, profile_input).await?;

    tx.commit().await
}
```

### Input struct for multi-step operations
```rust
pub struct TransferCreditsInput {
    pub from_id: i64,
    pub to_id: i64,
    pub amount: i64,
}

impl User {
    pub async fn transfer_credits(
        transaction: &mut Transaction<'_, Postgres>,
        input: TransferCreditsInput,
    ) -> anyhow::Result<()> {
        let TransferCreditsInput { from_id, to_id, amount } = input;

        sqlx::query!("UPDATE users SET credits = credits - $1 WHERE id = $2", amount, from_id)
            .execute(&mut **transaction)
            .await?;

        sqlx::query!("UPDATE users SET credits = credits + $1 WHERE id = $2", amount, to_id)
            .execute(&mut **transaction)
            .await?;

        Ok(())
    }
}
```

### Creating related entities
```rust
pub struct CreateUserWithProfileInput {
    pub email: String,
    pub bio: String,
}

impl User {
    pub async fn create_with_profile(
        transaction: &mut Transaction<'_, Postgres>,
        input: CreateUserWithProfileInput,
    ) -> anyhow::Result<i64> {
        let CreateUserWithProfileInput { email, bio } = input;

        let user_id = sqlx::query_scalar!(
            "INSERT INTO users (email) VALUES ($1) RETURNING id",
            email
        )
        .fetch_one(&mut **transaction)
        .await?;

        sqlx::query!(
            "INSERT INTO profiles (user_id, bio) VALUES ($1, $2)",
            user_id,
            bio
        )
        .execute(&mut **transaction)
        .await?;

        Ok(user_id)
    }
}
```

Note: Transaction automatically rolls back if dropped without calling `commit()`. The caller is responsible for calling `tx.commit().await`.
