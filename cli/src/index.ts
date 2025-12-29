#!/usr/bin/env node
import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import os from 'os';

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

  // Spawn the Zig binary, passing all arguments through
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

main();
