/**
 * Загрузчик переменных окружения.
 *
 * Порядок (значения позже — важнее):
 *   1. `.env`         — базовый, под версионным контролем (общие дефолты).
 *   2. `.env.local`   — локальный, НЕ под версионным контролем (gitignore),
 *                       переопределяет `.env`. Сюда кладут личные креды (S3 и т.п.).
 *
 * Файлы ищутся по очереди в нескольких каталогах (cwd и каталог бэкенд-пакета),
 * чтобы работало и при запуске через `npm run --workspace=apps/backend`
 * (cwd = apps/backend), и через `node dist/main` (cwd = /app, __dirname = dist).
 *
 * Внешние переменные окружения (прод-контейнер, systemd) имеют наивысший
 * приоритет: dotenv без override не перезаписывает уже заданные process.env.* —
 * поэтому прод-значения из окружения всегда побеждают оба файла.
 */
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';

const candidates = Array.from(
  new Set([process.cwd(), path.resolve(__dirname, '..')]),
);

let baseLoaded = false;
for (const dir of candidates) {
  const envPath = path.join(dir, '.env');
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath });
    baseLoaded = true;
  }

  const localPath = path.join(dir, '.env.local');
  if (fs.existsSync(localPath)) {
    // override:true — значения из .env.local перезаписывают .env.
    // Внешние process.env значения при этом dotenv НЕ трогает (не переопределяет).
    dotenv.config({ path: localPath, override: true });
  }
}

// Подстраховка: если ни один .env не найден — поведение по умолчанию (no-op).
if (!baseLoaded) {
  dotenv.config();
}