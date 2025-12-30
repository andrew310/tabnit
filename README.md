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

Once linked, you can run `tabnit` from anywhere:

```bash
# Initialize or generate a migration
tabnit up ./sql/schema.sql
```

## 🏛️ What's in a Name?

The name **Tabnit** (pronounced *tab-neet*) has deep roots in the ancient Near East:

*   **The Blueprint:** In Koine Hebrew, *Tabnit* means **"Pattern," "Blueprint," or "Structure."** It is the word used in ancient texts to describe the architect's plan for a building or temple.
*   **The Likeness:** In Phoenician, the language of the great sea-faring builders, it means **"Likeness" or "Image."**
*   **The Mummy King:** It was also the name of a famous Phoenician King of Sidon. His sarcophagus is unique because it is "bilingual"—featuring original Egyptian hieroglyphics alongside his own Phoenician metadata.

## 📜 License

MIT