import { defineConfig } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const __dirname = path.basename(process.cwd()) === 'e2e'
  ? process.cwd()
  : path.resolve(process.cwd(), 'e2e');

function loadEnvFile(filePath: string): Record<string, string> {
  if (!fs.existsSync(filePath)) return {};
  const content = fs.readFileSync(filePath, 'utf8');
  const env: Record<string, string> = {};
  for (const line of content.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eqIdx = trimmed.indexOf('=');
    if (eqIdx === -1) continue;
    const key = trimmed.slice(0, eqIdx).trim();
    const val = trimmed.slice(eqIdx + 1).trim();
    env[key] = val.replace(/^"|"$/g, '').replace(/^'|'$/g, '');
  }
  return env;
}

const envPath = path.resolve(__dirname, '.env');
const envVars = loadEnvFile(envPath);
Object.entries(envVars).forEach(([k, v]) => {
  if (process.env[k] === undefined || process.env[k] === '') process.env[k] = v;
});

// ── Browser mode (env-controlled) ─────────────────────────────────
const E2E_USE_BROWSER = (process.env.E2E_USE_BROWSER ?? 'true').toLowerCase() !== 'false';
const E2E_HEADLESS = (process.env.E2E_HEADLESS ?? 'false').toLowerCase() === 'true';

// Global setup runs in headless and API-only modes (resets DB + starts backend).
// In CDP mode (default: E2E_USE_BROWSER=true + E2E_HEADLESS=false) the user
// manages Chrome + backend, so global setup is skipped.
const SKIP_GLOBAL_SETUP = E2E_USE_BROWSER && !E2E_HEADLESS;

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  timeout: 30_000,
  workers: 1,
  reporter: process.env.CI ? 'list' : [['list'], ['html']],
  use: {
    browserName: 'chromium',
    headless: E2E_HEADLESS,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  globalSetup: SKIP_GLOBAL_SETUP ? undefined : './global-setup.ts',
});
