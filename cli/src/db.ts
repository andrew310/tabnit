import { Client } from 'pg';
import fs from 'fs';
import path from 'path';

export async function applyMigrations(migrationsDir: string) {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error("❌ DATABASE_URL environment variable is not set.");
    process.exit(1);
  }

  const client = new Client({ connectionString });
  
  try {
    await client.connect();
    
    // 1. Ensure tracking table exists
    await client.query(`
      CREATE TABLE IF NOT EXISTS tabnit_migrations (
        id SERIAL PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
      );
    `);

    // 2. Get applied migrations
    const res = await client.query('SELECT name FROM tabnit_migrations');
    const applied = new Set(res.rows.map(r => r.name));

    // 3. Find pending migrations
    if (!fs.existsSync(migrationsDir)) {
        console.log("No migrations directory found.");
        return;
    }

    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort(); // Lexicographical sort (timestamp based)

    const pending = files.filter(f => !applied.has(f));

    if (pending.length === 0) {
      console.log("✨ Database is up to date.");
      return;
    }

    console.log(`🚀 Found ${pending.length} pending migrations.`);

    // 4. Apply migrations in a transaction
    for (const file of pending) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');

      console.log(`▶️  Applying ${file}...`);
      
      try {
        await client.query('BEGIN');
        await client.query(sql);
        await client.query('INSERT INTO tabnit_migrations (name) VALUES ($1)', [file]);
        await client.query('COMMIT');
        console.log(`✅ Applied ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`❌ Failed to apply ${file}:`, err);
        process.exit(1);
      }
    }

    console.log("🎉 All migrations applied successfully.");

  } catch (err) {
    console.error("Database error:", err);
    process.exit(1);
  } finally {
    await client.end();
  }
}
