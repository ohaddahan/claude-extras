---
name: rust-sqlx
description: |
  Rust SQLx patterns for PostgreSQL. Covers compile-time checked queries (sqlx::query!),
  runtime queries with FromRow, migrations with sqlx-cli, offline mode with sqlx prepare,
  and idiomatic Rust coding style for database access. Use when: writing Postgres queries
  in Rust, setting up database migrations, debugging sqlx compile errors, or optimizing
  database code structure.
user-invocable: true
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(cargo:*), Bash(sqlx:*)
---

# Rust SQLx Skill (PostgreSQL)

## What this Skill is for
Use this Skill when:
- Writing database queries in Rust with sqlx
- Setting up or modifying PostgreSQL migrations
- Debugging compile-time query errors
- Structuring database access layers
- Using `sqlx prepare` for offline/CI builds
- Converting between compile-time and runtime queries

## Stack decisions (opinionated)

1. **Prefer compile-time queries (`query!`, `query_as!`)** when:
   - Query structure is known at compile time
   - You want maximum type safety
   - Working with fixed schemas

2. **Use runtime queries (`query`, `query_as`)** when:
   - Building dynamic WHERE clauses
   - Table/column names come from configuration
   - Prototyping before committing to schema

3. **Always use connection pools (`PgPool`)** in applications
   - Never pass raw connections around
   - Configure pool size based on workload

4. **Migrations via sqlx-cli**
   - Reversible migrations by default
   - Keep migrations small and focused
   - Never modify deployed migrations

## Operating procedure

### 1. Classify the task
- New query (compile-time vs runtime)
- Schema change (migration)
- Connection/pool setup
- CI/offline mode setup
- Error handling patterns

### 2. Pick the right pattern
- Compile-time: `query!`, `query_as!`, `query_scalar!`
- Runtime: `query`, `query_as` with `FromRow`
- Transactions: `pool.begin()` + `tx.commit()`
- Batch operations: `QueryBuilder` for bulk inserts

### 3. Follow struct conventions
- All fields public (per project rules)
- Derive `FromRow` for database structs
- Use dedicated input structs for 3+ parameters

### 4. Run verification
- `cargo sqlx prepare` after query changes
- `cargo check` to verify compile-time queries
- Test with actual database connection

## Progressive disclosure (read when needed)
- Compile-time and runtime queries: [queries.md](queries.md)
- Schema migrations: [migrations.md](migrations.md)
- Offline mode and sqlx prepare: [prepare.md](prepare.md)
- Coding patterns and style: [patterns.md](patterns.md)
