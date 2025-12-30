# Tabnit 📜

**Tabnit** treats SQL DDL as code. Skip the DSLs like Prisma or Drizzle—SQL is already great. Just write your schema and run `up`. Tabnit snapshots your local DDL to build migrations from your own source, eliminating drift and the headache of chasing remote DB differences.

## 🚀 Features

- **SQL as Source:** No DSLs, just pure PostgreSQL.
- **Blazing Fast:** Core parser written in Zig for maximum performance.
- **State-Based:** Automatic migration generation via DDL snapshots.
- **Robust:** Gracefully handles (and optionally ignores) `INSERT`, `INDEX`, and `TRIGGER` statements while focusing on the core schema.

## 📦 Installation

```bash
# Clone the repo
git clone https://github.com/andrew310/tabnit
cd tabnit

# Build the Zig binary
zig build

# Link the CLI globally
cd cli && npm install && npm link
```

## 🛠️ Usage

```bash
# 1. Baseline your project (creates snapshot)
tabnit init ./sql

# 2. Generate a migration after editing SQL
tabnit up ./sql

# 3. Apply pending migrations to your database
export DATABASE_URL=postgres://user:pass@localhost:5432/db
tabnit apply
```

## 🏛️ What's in a Name?

In Canaanite languages, the word **Tabnit** tended to mean **"Blueprint," "Pattern," or "Structure."** Like its namesake, this library acts as a bridge, taking your SQL code and turning it into a living blueprint for your database.

## 📜 License

MIT