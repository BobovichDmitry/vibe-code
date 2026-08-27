import { test, expect } from '@playwright/test';
import axios from 'axios';

// Nuxt SSR edge (3000), backend API (3001). History-роутинг (без #).
const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';
const API_URL = process.env.E2E_API_URL || 'http://localhost:3001/api';

// Unique user name for this test run (avoids conflicts with previous runs)
const TEST_USER_LOGIN = `test-user-${Date.now()}`;

test.describe('Basic smoke tests', () => {

  // ── Test 1: Login to admin panel ──────────────────────────────────
  // Cookie-auth: backend ставит httpOnly cookie на /api/auth/login,
  // Playwright context хранит её автоматически — /admin доступен без localStorage.
  test('should login to admin panel and redirect to users page', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);
    await page.getByPlaceholder('admin').waitFor({ state: 'visible', timeout: 10_000 });

    await page.getByPlaceholder('admin').fill('admin');
    await page.getByPlaceholder('••••••••').fill('admin123');
    await page.getByRole('button', { name: 'Войти' }).click();

    // History-роутинг — ждём /admin (без #).
    await page.waitForURL(/\/admin$/, { timeout: 15_000 });
    await expect(page.getByRole('heading', { name: 'Пользователи' })).toBeVisible({ timeout: 10_000 });
  });

  // ── Test 2: Create a new user via UI ──────────────────────────────
  test('should create a new user', async ({ page }) => {
    await page.goto(`${BASE_URL}/login`);
    await page.getByPlaceholder('admin').fill('admin');
    await page.getByPlaceholder('••••••••').fill('admin123');
    await page.getByRole('button', { name: 'Войти' }).click();
    await page.waitForURL(/\/admin$/, { timeout: 15_000 });
    await page.getByRole('heading', { name: 'Пользователи' }).waitFor({ state: 'visible', timeout: 10_000 });

    await page.getByRole('button', { name: 'Создать пользователя' }).click();

    await page.getByPlaceholder('username').fill(TEST_USER_LOGIN);
    await page.getByPlaceholder('Минимум 4 символа').fill('test1234');
    await page.getByRole('button', { name: 'Создать' }).click();

    await expect(page.getByRole('cell', { name: TEST_USER_LOGIN, exact: true })).toBeVisible({ timeout: 10_000 });
  });

  // ── Test 3: Public page shows user count (SSR) ───────────────────
  test('should show user count on public page', async ({ page }) => {
    const loginRes = await axios.post(`${API_URL}/auth/login`, {
      login: 'admin',
      password: 'admin123',
    });
    const token = loginRes.data.access_token;

    try {
      await axios.post(`${API_URL}/users`, {
        login: `test-user-public-${Date.now()}`,
        password: 'test1234',
        role: 'user',
      }, { headers: { Authorization: `Bearer ${token}` } });
    } catch {
      // Ignore if user already exists
    }

    // Публичная страница — SSR: счётчик уже в HTML с сервера.
    await page.goto(`${BASE_URL}/`);
    await page.waitForSelector('text=Всего пользователей', { timeout: 10_000 });

    const countElements = await page.locator('[class*="text-5xl"]').allTextContents();
    const count = parseInt(countElements[0] || '0', 10);
    expect(count).toBeGreaterThan(0);
  });

});