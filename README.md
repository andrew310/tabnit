# Tabnit 📜 (תַּבְנִית)

**Tabnit** is a high-performance PostgreSQL DDL parser written in Zig, wrapped in a TypeScript CLI. It recursively scans your SQL files and produces a structured AST (Abstract Syntax Tree) representing your tables, types, schemas, and functions.

## 🏛️ What's in a Name?

The name **Tabnit** (pronounced *tab-neet*) has deep roots in the ancient Near East:

*   **The Blueprint:** In Koine Hebrew, *Tabnit* (תַּבְנִית) means **"Pattern," "Blueprint," or "Structure."** It is the word used in ancient texts to describe the architect's plan for a building or temple.
*   **The Likeness:** In Phoenician (𐤕𐤁𐤍𐤕), the language of the great sea-faring builders, it means **"Likeness" or "Image."**
*   **The Mummy King:** It was also the name of a famous Phoenician King of Sidon. His sarcophagus is unique because it is "bilingual"—featuring original Egyptian hieroglyphics alongside his own Phoenician metadata.

Like its namesake, this library acts as a **bilingual bridge**, taking the "engraved stone" of SQL and turning it into a "living blueprint" (AST) for modern TypeScript applications.

## 🚀 Features

- **Blazing Fast:** Core parser written in Zig for maximum performance.
- **Recursive:** Point it at a directory, and it unrolls every `.sql` file it finds.
- **Postgres-First:** Supports specific PG syntax like `DO $$` blocks, `GENERATED ALWAYS AS IDENTITY`, `ENUM` types, and `SCHEMA` qualification.
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

Once linked, you can run `tabnit` from anywhere:

```bash
# Scan a single file
tabnit schema.sql

# Scan an entire directory recursively
tabnit ./sql/tables

# Use with your project
tabnit ~/.path/to/my/migrations
```

## 📜 License

MIT
