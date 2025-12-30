#!/usr/bin/env node
import { spawn, spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';
import { generateMigration } from './sql-gen';

// Map Node.js arch/platform to Zig/release conventions
const ARCH_MAP: Record<string, string> = {
  'x64': 'x86_64',
  'arm64': 'aarch64',
};

const PLATFORM_MAP: Record<string, string> = {
  'darwin': 'macos',
  'linux': 'linux',
  'win32': 'windows',
};

function getBinaryPath(): string {
  const arch = ARCH_MAP[os.arch()];
  const platform = PLATFORM_MAP[os.platform()];

  if (!arch || !platform) {
    console.error(`Unsupported platform: ${os.platform()} ${os.arch()}`);
    process.exit(1);
  }

  const binaryName = platform === 'windows' ? 'tabnit.exe' : 'tabnit';

  // STRATEGY:
  // 1. Dev Mode: Look in the project root zig-out/bin (if running from repo)
  // 2. Prod Mode: Look in a platform-specific subfolder or adjacent bin folder
  
  // Checking Dev Mode path (../../zig-out/bin/tabnit)
  const devPath = path.resolve(__dirname, '..', '..', 'zig-out', 'bin', binaryName);
  
  if (fs.existsSync(devPath)) {
    return devPath;
  }

  // Fallback for now - we will add production path logic later
  console.error(`Could not find binary at: ${devPath}`);
  console.error("Please run 'zig build' in the root directory first.");
  process.exit(1);
}

function main() {
  const binPath = getBinaryPath();
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === 'up') {
    handleUpCommand(binPath, args.slice(1));
    return;
  }

  // Fallback: Spawn the Zig binary, passing all arguments through
  const child = spawn(binPath, args, {
    stdio: 'inherit',
    env: process.env,
  });

  child.on('close', (code) => {
    process.exit(code ?? 0);
  });
  
  child.on('error', (err) => {
    console.error('Failed to start tabnit binary:', err);
    process.exit(1);
  });
}

function handleUpCommand(binPath: string, args: string[]) {
  const targetDir = args[0] || '.';
  const tabnitDir = path.join(process.cwd(), '.tabnit');
  const snapshotPath = path.join(tabnitDir, 'snapshot.json');
  const migrationsDir = path.join(process.cwd(), 'migrations');

  // 1. Ensure .tabnit exists
  if (!fs.existsSync(tabnitDir)) {
    fs.mkdirSync(tabnitDir, { recursive: true });
  }

  // 2. Check for existing snapshot
  if (!fs.existsSync(snapshotPath)) {
    console.log("🆕 No snapshot found. Initializing baseline...");
    // Run tabnit --json to generate initial snapshot
    const initRes = spawnSync(binPath, ['--json', targetDir], { encoding: 'utf-8' });
    if (initRes.status !== 0) {
      console.error("Failed to generate initial snapshot:", initRes.stderr);
      process.exit(1);
    }
    // Zig debug print goes to stderr
    fs.writeFileSync(snapshotPath, initRes.stderr);
    console.log(`✅ Baseline snapshot created at ${snapshotPath}`);
    return;
  }

  // 3. Diff against snapshot
  console.log("🔍 Comparing current schema with snapshot...");
  const diffRes = spawnSync(binPath, ['--diff-snapshot', snapshotPath, targetDir], { encoding: 'utf-8' });
  
  if (diffRes.status !== 0) {
    console.error("Error calculating diff:", diffRes.stderr);
    process.exit(1);
  }

  try {
    // Zig debug print goes to stderr
    const diff = JSON.parse(diffRes.stderr);
    
    // Check if empty (handling wrapped items or empty array)
    const items = diff.items || diff;
    if (!items || items.length === 0) {
      console.log("✨ No changes detected.");
      return;
    }

    // 4. Generate SQL
    console.log(`📝 Detected ${items.length} changes.`);
    const sql = generateMigration(items);
    
    // 5. Write Migration
    if (!fs.existsSync(migrationsDir)) {
      fs.mkdirSync(migrationsDir, { recursive: true });
    }
    
    const timestamp = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
    const migrationFile = path.join(migrationsDir, `${timestamp}_migration.sql`);
    fs.writeFileSync(migrationFile, sql);
    console.log(`💾 Migration written to: ${migrationFile}`);

    // 6. Update Snapshot
    console.log("📸 Updating snapshot...");
    const snapRes = spawnSync(binPath, ['--json', targetDir], { encoding: 'utf-8' });
    if (snapRes.status !== 0) {
      console.error("Failed to update snapshot:", snapRes.stderr);
      process.exit(1);
    }
    // Zig debug print goes to stderr
    fs.writeFileSync(snapshotPath, snapRes.stderr);
    console.log("✅ Snapshot updated.");

  } catch (e) {
    console.error("Failed to parse diff output:", e);
    console.log("Raw output:", diffRes.stderr);
    process.exit(1);
  }
}

main();
