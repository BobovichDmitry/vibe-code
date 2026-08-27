# Project Overview

## Описание

Шаблон Nest.js + Vue 3 приложения с авторизацией, админ-панелью управления пользователями и файлами, и публичной страницей со счётчиком пользователей. Публичная часть показывает текущее количество пользователей. Админ-панель (под авторизацией): управление пользователями (просмотр, создание, удаление) и файлами (загрузка в S3, фильтр/пагинация, скачивание, удаление).

**Стек**: Nest.js + Express (backend), Vue 3 + Tailwind CSS (frontend), SQLite (dev) / PostgreSQL (prod), JWT auth, AWS SDK v3 (S3-совместимое хранилище), Playwright e2e tests (CDP).

## Стек

| Слой | Технология | Версия |
|------|-----------|--------|
| Бэкенд | Nest.js + Express | ^11.0.0 |
| ORM | TypeORM | ^0.3.20 |
| БД | SQLite (dev) / PostgreSQL (prod) | — |
| Фронтенд | Vue 3 + Composition API | ^3.5.0 |
| Стилизация | Tailwind CSS | ^3.4.17 |
| Маршрутизация | Vue Router (hash history) | ^4.5.0 |
| HTTP-клиент | Axios | ^1.7.0 |
| Хранилище файлов | AWS SDK v3 (S3-совместимое) | `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner` |
| E2E-тесты | Playwright + Chrome CDP | ^1.48.0 |
| Авторизация | JWT (passport-jwt) | — |
| Сборка | Vite (frontend) + Nest CLI (backend) | — |
| Контейнеризация | Docker multi-stage | node:22-alpine |

## Монорепо (npm workspaces)

```
project/
├── apps/
│   ├── backend/          # Nest.js API (@Controller + TypeORM)
│   │   ├── src/auth/     # JWT auth (login, me, password)
│   │   ├── src/users/    # User CRUD (admin only)
│   │   ├── src/files/    # Файлы в S3 (presigned-URL, прямая загрузка)
│   │   ├── src/env.ts    # Загрузчик env (.env → .env.local override)
│   │   └── src/main.ts   # Entry, cookie-parser, CORS, порт 3001
│   └── frontend/         # Nuxt 3 SSR (Nitro + Tailwind, история-роутинг)
│       ├── pages/         # Nuxt file-based routing (index, login, admin/index, admin/files)
│       ├── layouts/      # default.vue + admin.vue (сайдбар)
│       ├── composables/   # useApi (SSR $fetch), useAuth (cookie JWT), useBranding, useTheme
│       ├── middleware/    # auth, guest
│       └── plugins/       # theme.server / theme.client (SSR-safe тема, без FOUC)
├── e2e/                  # Playwright e2e tests (CDP)
├── docker/               # Dockerfile.frontend + Dockerfile.backend + compose
├── scripts/              # Helpers: log-runner, kill-service
└── package.json          # Root workspace
```

## Entry Points

| Приложение | Entry point | Описание |
|-----------|-------------|----------|
| Backend | `apps/backend/src/main.ts` | Nest.js bootstrap, cookie-parser, CORS, порт 3001 |
| Frontend | `apps/frontend/app.vue` | Nuxt SSR корень (брендинг useHead + NuxtLayout) |
| E2E | `e2e/playwright.config.mts` | Playwright config (chromium-remote) |

## Архитектурные решения

1. **Два отдельных сервиса**: frontend (Nuxt 3 SSR/Nitro, порт 3000, edge) + backend (Nest API, порт 3001, внутренний). Nuxt проксирует `/api/**` → backend (nitro `routeRules`). Nest больше не раздаёт статику — чистый API. Frontend можно вынести на отдельный сервер сменой `NUXT_API_BASE`.
2. **API prefix**: `setGlobalPrefix('api')` — все API-маршруты под `/api/*`.
3. **History-роутинг (Nuxt)**: file-based routing, хеш-роутинг убран. Публичная часть — полноценный SSR (`useAsyncData`/`useHead`).
4. **Database abstraction**: `DB_TYPE=sqlite` или `postgres` через `.env`. TypeORM `synchronize: true` (dev) / миграции (prod).
5. **E2E через CDP**: Playwright подключается к реальному Chrome (`--remote-debugging-port=9222`), не к headless.
6. **JWT auth (cookie + Bearer)**: httpOnly cookie `auth_token` (ставит `/api/auth/login`) **И** Bearer — обратно-совместимо. 24h expiry. `POST /api/auth/logout` чистит cookie.
7. **Role-based access**: Роли `admin` и `user`. Только `admin` может CRUD пользователей.
8. **Seeding**: Первый админ создаётся автоматически при пустой БД (из `ADMIN_LOGIN` / `ADMIN_PASSWORD` из env).
9. **Файлы в S3**: Модуль `FilesModule` работает с S3-совместимым хранилищем через AWS SDK v3 (presigned-PUT/GET + прямая загрузка). Без sharp/ресайза. Конфиг — из `S3_*` env.
10. **.env.local**: Базовый `.env` под git, `.env.local` (не под git) переопределяет его; внешнее окружение — наивысший приоритет. Загрузчик `apps/backend/src/env.ts`.

## Порты

| Порт | Назначение |
|------|-----------|
| 3000 | Frontend (Nuxt SSR, edge) — production и dev |
| 3001 | Backend (Nest API, внутренний) — production и dev |
| 9222 | Chrome CDP (для e2e тестов) |
| 8080 | Playwright UI (в Docker e2e) |

## Ключевые команды

| Команда | Описание |
|---------|----------|
| `npm install` | Все зависимости |
| `npm run dev:backend:log` | Backend с логированием |
| `npm run dev:frontend:log` | Frontend с логированием |
| `npm run build` | Обе сборки |
| `npm run start:prod` | Production (Nest + static) |
| `npm run test:e2e` | E2E тесты (последовательно, `workers=1`) |
| `npm run db:reset` | Сброс БД |
| `npm run create-admin` | CLI: создать админа |