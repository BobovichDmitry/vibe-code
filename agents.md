# VibeSetup UI — Agent Guide

## Architecture

**Monorepo** (npm workspaces) с Nest.js backend, **Nuxt 3 frontend (SSR)**, Playwright e2e. В проде — **два отдельных сервиса**: frontend (Nuxt/Nitro, порт **3000**, edge за nginx-proxy) и backend (Nest API, порт **3001**, внутренний). Nuxt проксирует `/api/**` → backend (nitro `routeRules`). Frontend можно вынести на отдельный сервер без правок кода (смена `NUXT_API_BASE`).

```
vibe-setup-ui/
├── apps/
│   ├── backend/          # Nest.js API (/api/auth, /api/users)
│   │   ├── src/
│   │   │   ├── main.ts                 # Entry, global prefix 'api', cookie-parser, порт 3001
│   │   │   ├── app.module.ts           # Root module, seeds DB on startup
│   │   │   ├── database/               # SQLite/PostgreSQL TypeORM config
│   │   │   ├── auth/                   # JWT auth (login + set cookie, me, password, logout)
│   │   │   │   ├── auth.controller.ts   # set/clear httpOnly cookie `auth_token`
│   │   │   │   ├── auth.service.ts
│   │   │   │   ├── jwt.strategy.ts       # Bearer + cookie extractors
│   │   │   │   └── jwt-auth.guard.ts     # Bearer + cookie extractors
│   │   │   ├── health/                 # GET /api/health (public healthcheck)
│   │   │   ├── files/                  # Files in S3 (presigned-URL, upload)
│   │   │   │   ├── entities/file.entity.ts
│   │   │   │   ├── file.service.ts
│   │   │   │   ├── files.controller.ts
│   │   │   │   └── files.module.ts
│   │   │   ├── users/                  # User CRUD (admin only)
│   │   │   │   ├── entities/user.entity.ts
│   │   │   │   ├── users.controller.ts
│   │   │   │   ├── users.service.ts
│   │   │   │   └── users.module.ts
│   │   │   └── env.ts                  # Env loader (.env → .env.local override)
│   │   └── .env                        # DB_TYPE, DB_* settings, PORT=3001, S3_*, COOKIE_SECURE
│   └── frontend/         # Nuxt 3 (SSR) + Tailwind
│       ├── nuxt.config.ts             # routeRules прокси /api → backend:3001, runtimeConfig
│       ├── app.vue                    # Корень: брендинг (useHead) + NuxtLayout/NuxtPage
│       ├── pages/                     # file-based routing (history): index, login, admin/{index,files}
│       ├── layouts/                   # default.vue (хедер), admin.vue (сайдбар)
│       ├── components/ThemeToggle.vue
│       ├── composables/               # useApi (SSR $fetch), useAuth (cookie), useBranding, useTheme
│       ├── middleware/                # auth.ts, guest.ts
│       ├── plugins/                   # theme.server.ts (без FOUC), theme.client.ts
│       ├── assets/css/style.css       # Tailwind directives
│       └── .env, .env.local.example    # PORT, NUXT_PUBLIC_API_BASE, NUXT_API_BASE
├── e2e/                    # Playwright e2e tests (remote Chrome CDP)
│   ├── fixtures.ts          # test.extend: connectedBrowser, connectedPage
│   ├── global-setup.ts      # Checks Chrome CDP, seeds DB via API
│   ├── tests/basic.spec.ts  # Login → create user → check count (history-роутинг, cookie)
│   ├── playwright.config.mts
│   └── .env                 # BROWSER_PORT, REMOTE_CHROME_HOST, E2E_BASE_URL=:3000, E2E_API_URL=:3001
├── docker/
│   ├── Dockerfile.frontend # Nuxt build → Nitro server (порт 3000)
│   ├── Dockerfile.backend  # Nest build (порт 3001)
│   ├── docker-compose.yml   # Dev: frontend + backend + postgres (порты проброшены)
│   ├── nginx/                   # edge-nginx: conf.d/edge.conf + runtime/upstream-frontend.conf
│   ├── deploy_0downtime.sh      # Blue-green деплой без простоя (активный слот в .active-slot, gitignored)
│   ├── docker-compose.prod.yml  # Prod blue-green: edge-nginx + слоты frontend/backend blue/green + postgres
│   ├── docker-compose.e2e.yml  # E2E tests with Playwright UI (:8080)
│   ├── docker-compose.nginx-proxy.yml  # Legacy variant
│   └── env                  # Production env template (backend + compose-интерполяция)
├── ansible/                # Ansible-деплой (запуск НА сервере)
│   ├── ansible.cfg          # inventory, host_key_checking=False
│   ├── inventory.ini        # localhost, ansible_connection=local
│   ├── group_vars/all.yml   # Переменные (плейсхолдеры/выводимые из project_name; prod_compose_file, cors_origin)
│   ├── vars.example.yml     # Пример заполнения переменных
│   ├── playbook.yml         # Плейбук (tags: deps, proxy, deploy, healthcheck через edge-nginx)
│   ├── roles/               # docker, nginx_proxy, app
│   ├── templates/           # env.j2 (PORT=3001, CORS, COOKIE_SECURE), compose-proxy.yml.j2
│   └── README.md            # Инструкция: sftp архива + запуск на сервере
├── docs/                   # Documentation
│   ├── GETTING_STARTED.md   # Full setup guide (Docker, nginx-proxy, local)
│   ├── deployment.md        # Deploy, env vars, ports (3000/3001), checklists
│   ├── testing-guide.md     # Testing guide
│   ├── agents.md            # Agent quick reference
│   ├── project-overview.md  # Architecture overview
│   ├── context-index.md     # Doc index
│   └── areas/               # Area-specific docs
│       ├── backend-api-structure.md
│       ├── blue-green-deploy.md    # Blue-green деплой без простоя (edge-nginx, deploy_0downtime.sh)
│       ├── auth-structure.md
│       ├── database-structure.md
│       ├── frontend-structure.md   # Nuxt 3 SSR
│       ├── nuxt-migration.md       # Гайд миграции Vite SPA → Nuxt 3 SSR
│       ├── admin-panel.md
│       └── e2e-testing-structure.md
├── scripts/
│   ├── log-runner.mjs       # Runs service with logging to logs/<name>.log
│   ├── kill-service.mjs     # Kills service by PID file
│   ├── encrypt.sh <env>     # Шифрует .envs/<env>/secret.yaml → secret.enc.yaml (SOPS+age)
│   └── decrypt.sh <env>     # Расшифровывает .envs/<env>/secret.enc.yaml → secret.yaml
├── .envs/
│   ├── test/                # public.yaml + secret.enc.yaml (SOPS+age), secret.yaml gitignored
│   └── production/          # то же для прода
├── deploy.sh               # Локальный деплой (env-driven, PROJECT_NAME обязателен)
├── package.json             # Root workspace, all scripts
└── agents.md                # ← This file
```

## Commands

### Dev (user runs these manually)

| Command | Description |
|---------|-------------|
| `npm run dev:backend:log` | Start backend with logging → `logs/backend.log` (PID in `logs/backend.pid`) |
| `npm run dev:frontend:log` | Start frontend with logging → `logs/frontend.log` (PID in `logs/frontend.pid`) |
| `npm run kill:backend` | Kill backend and its process tree (reads `logs/backend.pid`) |
| `npm run kill:frontend` | Kill frontend and its process tree (reads `logs/frontend.pid`) |

Log files rotate at 10 MB: `backend.log` → `backend.1.log` → … → `backend.5.log` (deleted).

### Agent: DO NOT start services (default rule)

The user runs `dev:*:log` and `kill:*` commands manually. **Do NOT start backend or frontend yourself** — ask the user to run the command (e.g. `npm run dev:backend:log`) if a service needs to be running.

**Exception**: If the user explicitly asks you to start/stop a service in their message, then you may run the command yourself.

When debugging a problem, read the logs instead:
- `logs/backend.log` — current backend log
- `logs/frontend.log` — current frontend log
- `logs/deploy.log` — deployment log (`./deploy.sh`, manual deploy)
- `logs/deploy-ci.log` — deployment log (`docker/deploy_ci.sh`, CI deploy)
- Both deploy scripts end with a marker line in stdout AND in the log file: `### DEPLOY-FINISHED: ... (exit 0) ###` (success) or `### DEPLOY-FAILED: ... (exit N) ###` (failure). To check whether a deploy has finished: `grep -E 'DEPLOY-(FINISHED|FAILED)' logs/deploy.log | tail -1`
- `logs/backend.pid` / `logs/frontend.pid` — process IDs (if present, the service is running)

### Build & Prod

| Command | Description |
|---------|-------------|
| `npm install` | Install all workspace deps |
| `npm run build:frontend` | Build Nuxt → `apps/frontend/.output/` (Nitro server) |
| `npm run build:backend` | Build Nest → `apps/backend/dist/` |
| `npm run build` | Both builds |
| `npm run typecheck` | `nuxt typecheck` + `tsc --noEmit` (оба workspace) |
| `npm run start:prod` | Production backend (Nest, 3001) — frontend отдельным процессом (Nitro) |
| `npm run test:e2e` | Run Playwright tests against running app |
| `npm run db:reset` | Reset DB (dev: drop + synchronize) |
| `npm run db:recreate` | Recreate DB (prod-prep: drop + миграции) |
| `npm run migration:run` | Накатить pending-миграции (TypeORM CLI) |
| `npm run migration:revert` | Откатить последнюю миграцию |
| `npm run migration:generate -- src/migrations/Name` | Сгенерировать миграцию из diff |

### Ручной деплой с локальной машины (без CI) — `deploy_local.sh`

Полный цикл деплоя на прод **с этой машины**, минуя GitLab CI. Для отладки деплоймента — не жди раннеров:

```bash
# Стандартный запуск (production, образы :<sha HEAD> из Registry):
CI_JOB_TOKEN=glpat-... bash deploy_local.sh

# Образы конкретной ревизии (когда CI выключен и HEAD не собран):
CI_JOB_TOKEN=glpat-... IMAGE_SHA=83d513bb bash deploy_local.sh

# Явные теги образов / тест-стенд / без docker login:
FRONTEND_IMAGE=... BACKEND_IMAGE=... bash deploy_local.sh
DEPLOY_ENV=test bash deploy_local.sh
DEPLOY_SKIP_LOGIN=1 bash deploy_local.sh
```

Требуется: `.envs/<env>/.agekey` (age-ключ стенда, per-env, gitignored) + PAT с `read_registry` в `CI_JOB_TOKEN`.
Поток: расшифровка `.envs/<env>/secret.enc.yaml` → архив исходников → SSH → ansible →
`docker/deploy_0downtime.sh --pull` (blue-green переключение). Лог: `logs/deploy-local-run.log` (или задай свой через tee).

**Что происходит на сервере** (см. `docs/areas/blue-green-deploy.md`): поднимается standby-слот
(frontend+backend парой) → healthcheck `/api/health` → edge-nginx переключает upstream (`nginx -s reload`)
→ верификация → останов старого слота. Состояние — `<project>/docker/.active-slot`. При ошибке — откат
upstream на живой слот (`✗ ... / Rollback` в выводе).

**Отладка деплоя на сервере** (SSH: `root@31.77.193.104`, профиль `default` в ssh-connect MCP):

```bash
cd /opt/gmoreva-setup/docker
cat .active-slot                                  # активный слот (blue/green)
docker ps --format 'table {{.Names}}\t{{.Status}}' # слоты + health
grep server nginx/runtime/upstream-frontend.conf  # куда смотрит edge-nginx
docker compose -p gmoreva-setup -f docker-compose.prod.yml logs edge-nginx
docker compose -p gmoreva-setup -f docker-compose.prod.yml logs backend-blue
curl -k https://big-vibe.hopto.org/api/health     # сквозная проверка
```

**Грабли, уже собранные (не повторять):**
1. **Bind-mount каталогов, НЕ файлов** (nginx conf/runtime): tar-распаковка архива пересоздаёт
   файлы (новый inode) — file-mount остаётся на старом inode, nginx видит устаревший upstream.
2. **Healthcheck 127.0.0.1, НЕ localhost**: в alpine `localhost` резолвится в `::1`, Nitro/node
   слушают только IPv4 → контейнер вечно unhealthy.
3. **Nginx map `'' → ''`** (НЕ close) при keepalive-пуле: `Connection: close` + keepalive = мёртвые
   сокеты в пуле → чередование 200/400 Bad Request.
4. **Bootstrap**: upstream-файл из репо указывает на frontend-blue — при bootstrap поднимается
   standby; писать upstream в реально поднимаемый слот ДО старта edge-nginx (+ `--force-recreate`).
5. **CI выключен** (`workflow: when: never` в `.gitlab-ci.yml`) — образы не собираются на пуш.
   Для ручного деплоя указывай готовый `IMAGE_SHA` (последняя собранная ревизия) или собери образы
   вручную и запушь в Registry.

## Environment Variables

### Backend (`apps/backend/.env`)

**`.env.local` (не под версионным контролем)** переопределяет значения из `.env`. Создаётся рядом с `.env`, игнорируется git (корневой `.gitignore`: `.env.local`, `.env.*.local`). Сюда кладут локальные креды (S3/MinIO и т.п.). Шаблон: `apps/backend/.env.local.example`. Внешнее окружение (прод-контейнер, systemd) имеет наивысший приоритет — dotenv его не перезаписывает.

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_TYPE` | `sqlite` | `sqlite` or `postgres` |
| `DB_SYNCHRONIZE` | `true` | `true` = synchronize (dev), `false` = migrations (prod) |
| `DB_SQLITE_PATH` | `./data/database.sqlite` | SQLite file path |
| `DB_HOST` | `localhost` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USERNAME` | `postgres` | PostgreSQL user |
| `DB_PASSWORD` | `postgres` | PostgreSQL password |
| `DB_DATABASE` | `app_db` | PostgreSQL database name |
| `PORT` | `3001` | Backend (внутренний API) port (переопределяется в `.env.local`) |
| `JWT_SECRET` | `dev-secret-change-me` | **Change in production!** |
| `ADMIN_LOGIN` | `admin` | First admin (empty DB only) |
| `ADMIN_PASSWORD` | `admin` | First admin (empty DB only) |
| `CORS_ORIGIN` | `http://localhost:3000` | CORS allowed origins (Nuxt-origin) |
| `COOKIE_SECURE` | (empty) | Cookie-auth: secure=true в проде (HTTPS). Auto: false в dev. |
| `S3_ENDPOINT` | (empty) | S3-совместимое хранилище endpoint (напр. `https://s3.amazonaws.com`, MinIO) |
| `S3_PUBLIC_URL` | = `S3_ENDPOINT` | Endpoint для presigned-URL'ов (публичный домен, если отличается) |
| `S3_REGION` | `us-east-1` | Регион S3 |
| `S3_BUCKET` | (empty) | Имя бакета |
| `S3_ACCESS_KEY` | (empty) | Access key id |
| `S3_SECRET_KEY` | (empty) | Secret access key |
| `S3_KEY_PREFIX` | (empty) | Префикс-папка для рандомных ключей (напр. `uploads/`) |
| `S3_UPLOAD_EXPIRES` | `600` | Срок действия presigned PUT, сек |
| `S3_DOWNLOAD_EXPIRES` | `86400` | Срок действия presigned GET, сек |
| `S3_FORCE_PATH_STYLE` | `true` | `forcePathStyle` для S3Client (true для MinIO/самохоста) |

### Frontend (`apps/frontend/.env`)

Порты обоих сервисов задаются через `PORT` в `apps/<service>/.env.local`
(переопределяет `.env`; шаблон — `.env.local.example` в папке сервиса). При смене
порта backend обновите и `NUXT_API_BASE` у frontend (и наоборот — `CORS_ORIGIN` у backend).

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | Порт dev-сервера frontend (nuxt dev; только для dev — в проде используется `NITRO_PORT`) |
| `NUXT_PUBLIC_API_BASE` | `/api` | Клиентский base (через Nitro прокси) |
| `NUXT_API_BASE` | `http://localhost:3001/api` | Серверный base при SSR (прямой fetch к backend) |

### E2E (`e2e/.env`)
| Variable | Default | Description |
|----------|---------|-------------|
| `BROWSER_PORT` | `9222` | Chrome remote debugging port |
| `REMOTE_CHROME_HOST` | `localhost` | Chrome host for CDP |
| `E2E_BASE_URL` | `http://localhost:3000` | App URL (Nuxt SSR edge) |
| `E2E_API_URL` | `http://localhost:3001/api` | API URL (backend Nest) |

**REMOTE_DEBUGGING_URL** is derived: `http://${REMOTE_CHROME_HOST}:${BROWSER_PORT}`

## Key Design Decisions

1. **Два отдельных сервиса**: frontend (Nuxt SSR/Nitro, порт 3000, edge) + backend (Nest API, порт 3001, внутренний). Nuxt проксирует `/api/**` → `http://backend:3001` (nitro `routeRules`). Nest больше не раздаёт статику — чистый API. Frontend можно вынести на отдельный сервер сменой `NUXT_API_BASE` (без правок кода). См. `docs/areas/nuxt-migration.md`.

2. **API prefix**: `setGlobalPrefix('api')` + `@Controller('auth')` / `@Controller('users')` — все API routes на `/api/*`.

3. **Database abstraction**: Two connectors (SQLite/PostgreSQL) via `DB_TYPE` env. Two modes: dev uses `synchronize: true` (fast iteration), prod uses migrations (`DB_SYNCHRONIZE=false` → `migrationsRun: true`, auto-run pending at startup). SQLite for local/dev, PostgreSQL for production. Baseline migration (`InitSchema`) creates the full schema in one migration. TypeORM CLI scripts: `migration:generate/run/revert`, `db:recreate`.

4. **E2E via CDP**: Tests connect to an already-running Chrome via `connectOverCDP`. No headless browser — tests run in your actual browser. Launch Chrome with `--remote-debugging-port=9222`.

5. **Playwright fixtures**: Custom `connectedBrowser` and `connectedPage` fixtures manage the CDP connection. Pages ARE closed after each test to keep the browser clean.

6. **JWT Auth (cookie + Bearer)**: httpOnly cookie `auth_token` (ставит `/api/auth/login`) **И** Bearer-заголовок — обратно-совместимо. Guard `@UseGuards(JwtAuthGuard)` принимает оба. 24h expiry. `POST /api/auth/logout` чистит cookie.

7. **Role-based access**: Roles `admin` and `user`. Only `admin` can CRUD users.

8. **History-роутинг (Nuxt)**: file-based routing, `createWebHashHistory` убран. Переходы — real history (`/admin`, `/login`). Публичная часть — полноценный SSR (`useAsyncData`/`useHead`).

9. **Seeding**: First admin created automatically on empty DB (from `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars).

## API Endpoints

### Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Login → `{ access_token }` + ставит httpOnly cookie `auth_token` |
| GET | `/api/auth/me` | Current user (JWT из cookie или Bearer) |
| PATCH | `/api/auth/password` | Change password (JWT required) |
| POST | `/api/auth/logout` | Clears httpOnly cookie `auth_token` |

### Users

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/users` | All users (admin only) |
| GET | `/api/users/:id` | Single user (admin only) |
| POST | `/api/users` | Create user (admin only) |
| PATCH | `/api/users/:id` | Update user (admin only) |
| DELETE | `/api/users/:id` | Delete user (admin only) |
| GET | `/api/users/count` | User count (public, no auth) |
| GET | `/api/health` | Public healthcheck (`health/health.controller.ts`) — для compose-healthcheck'ов и деплоя |
| GET | `/api/version` | Version + commit SHA (public, проверка деплоя) |

### Files

Все эндпоинты под JWT. `fileKey` передаётся через query (`?fileKey=...`) для поддержки ключей со слэшами. Прямая загрузка — multipart-поле `file`.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/files` | Список файлов (фильтр `search` по fileKey, пагинация `limit`/`offset`) → `{ items, total }` (JWT) |
| POST | `/api/files` | Прямая загрузка файла (multipart `file`) → `{ fileKey, fileId }` (создаёт `FileEntity`, `inStorage=true`) |
| POST | `/api/files/presigned-upload` | Запрос presigned PUT-URL (создаёт `FileEntity`, `inStorage=false`, без объекта-маркера) → `{ url, fileKey, fileId }` |
| POST | `/api/files/update-meta` | Подтянуть size/contentType из `headObject`, поставить `inStorage=true` |
| GET | `/api/files/presigned-url?fileKey=&disposition=&expiresIn=&filename=` | Presigned GET-URL → `{ url }` |
| GET | `/api/files/stream?fileKey=` | Стрим файла (`inline` Content-Disposition) |
| GET | `/api/files/download?fileKey=` | Скачивание файла (`attachment` Content-Disposition) |
| DELETE | `/api/files?fileKey=` | Удалить объект в S3 + запись в БД |

## Docker

```bash
# Dev (frontend + backend + postgres, порты проброшены)
cd docker && docker compose up -d

# Production via ansible (запуск НА сервере — см. ansible/README.md)
# Ansible ставит Docker, поднимает nginx-proxy, собирает и поднимает приложение
ansible-playbook playbook.yml -e @vars.yml

# E2E tests (Playwright UI on :8080)
cd docker && docker compose -f docker-compose.e2e.yml up e2e
```

- **`docker-compose.yml`** (dev): frontend (3000) + backend (3001) + PostgreSQL (5432 проброшен).
- **`docker-compose.prod.yml`** (prod, blue-green без простоя): **edge-nginx**
  (`nginx:1.27-alpine`, единственный `VIRTUAL_HOST` в reverse-proxy сети; конфиг
  `docker/nginx/conf.d/edge.conf`, upstream — `docker/nginx/runtime/upstream-frontend.conf`)
  + слоты `frontend-blue/backend-blue` и `frontend-green/backend-green`
  (YAML-якоря `x-frontend-common`/`x-backend-common`). Изолированные сети
  `slot_blue`/`slot_green` с одинаковыми aliases `frontend`/`backend` внутри каждой;
  общий postgres. Healthcheck'и: backend `/api/health`, frontend `/`.
  Обновление — `docker/deploy_0downtime.sh <project_name> --build|--pull`
  (вызывается ansible-ролью `app`): активный слот читается из `docker/.active-slot`
  (gitignored) → standby-слот build/pull + up + healthcheck → переключение upstream
  (`nginx -t` + reload) → верификация `/api/health` через edge-nginx → запись состояния
  → остановка старого слота (задержка `OLD_SLOT_STOP_DELAY`, по умолчанию 10с).
  Ошибка → rollback upstream на активный слот. Bootstrap (нет `.active-slot`):
  поднимается только новый слот. Telegram-нотификации при заданных `BOT_TOKEN` +
  `TELEGRAM_NOTIFY_CHAT` (опц. `TELEGRAM_NOTIFY_TOPIC`) в `docker/env`:
  start-сообщение → edit в итог (домен, коммит (SHA + сообщение до 20 симв.), слот, время, результат) + реакция 👍; не заданы —
  пропускаются молча. Сборка — на сервере внутри Docker (split Dockerfile'ы).
- **`app`** (`ansible/roles/app`): НЕ делает `docker compose up` напрямую — готовит
  окружение (env, `FRONTEND_IMAGE`/`BACKEND_IMAGE` в CI-режиме, postgres up +
  `pg_isready` + синхронизация пароля роли ДО старта слотов — рестарт backend не нужен)
  и вызывает `deploy_0downtime.sh` (`--pull` CI / `--build` ручной).
- **nginx-proxy** (`nginxproxy/nginx-proxy` + `nginxproxy/acme-companion`):
  общий reverse-proxy один раз на сервере (тег `proxy`). Мульти-проект —
  каждый edge-nginx подключается к `reverse-proxy` и объявляет свой `VIRTUAL_HOST`.

Dockerfile's (split, multi-stage):
- **`Dockerfile.frontend`**: deps → `nuxt build` → production (Nitro server, 3000).
- **`Dockerfile.backend`**: deps → `nest build` → production (Nest API, 3001).

## Writing E2E Tests

Tests import from `../fixtures` (NOT from `@playwright/test` directly):

```typescript
import { test, expect } from '../fixtures';
const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:3000';
const API_URL = process.env.E2E_API_URL || 'http://localhost:3001/api';

test('example', async ({ connectedPage }) => {
  await connectedPage.goto(`${BASE_URL}/`);
  // Use full URLs — baseURL doesn't apply with CDP connected pages
  expect(await connectedPage.locator('h1').first().textContent()).toContain('VibeSetup UI');
});
```

History-роутинг (без `#`): URL как `/admin`, `/login`. Cookie-auth: Playwright context хранит cookie после `POST /api/auth/login` автоматически.

You do not need to run e2e test after every change. Only when user asks you

## Browser Work: Delegate to Subagent

**NEVER call `chrome_devtools_*` tools directly.** All browser work (navigation, screenshots, DOM inspection, console logs, network requests, performance tracing) MUST be delegated to the `browser-checker` subagent via the `subagent` tool.

```typescript
// ✅ Correct — delegate to subagent
subagent({
  agent: "browser-checker",
  task: "Navigate to http://localhost:3000 and take a screenshot"
})

// ❌ WRONG — never call chrome_devtools_* directly
chrome_devtools_navigate_page({ url: "http://localhost:3000" })
```

## Subagents

Project-local subagents (stored in `.pi/agents/`). Call with `@<name> <message>`.

| Subagent | Invoke | When to use |
|----------|--------|-------------|
| `browser-checker` | `@browser-checker проверь страницу` | **All browser work** — navigation, screenshots, console logs, DOM inspection, network analysis. Never call chrome_devtools_* tools yourself; delegate to this subagent. |
| `docs-maintainer` | `@docs-maintainer обнови docs` | **After any code changes** — compares code with `docs/` and updates affected doc files. Use with a description of what changed, or without one to auto-detect drift. |
| `test-runner` | `@test-runner запусти тесты` | **Run e2e tests and return a compact report** — all tests, a specific file, or filtered by pattern. Returns pass/fail summary with error details. Does NOT fix code — only reports. |
| `test-fixer` | `@test-fixer почини тесты` | **Fix broken e2e tests** — runs the test, analyzes the error, fixes the root cause in code, re-runs, and returns the final report. Use after `test-runner` identifies failures. |

### browser-checker workflow

```text
User: проверь как выглядит публичная страница
Agent: subagent({ agent: "browser-checker", task: "Navigate to http://localhost:3000, take screenshot of public page" })
Subagent: opens browser → takes screenshot → checks console → reports findings
```

### docs-maintainer workflow

```text
User: добавь новый эндпоинт POST /api/users/import
Agent: <implements the endpoint>
User: @docs-maintainer обнови docs
Subagent: reads new code → updates docs/areas/backend-api-structure.md → lists changes
```

Without a description the subagent reads the code itself and compares it with existing docs.

### test-runner workflow

```text
User: запусти e2e тесты
Agent: subagent({ agent: "test-runner", task: "Запусти все e2e тесты и верни отчёт" })
Subagent: npx playwright test → reads output → returns summary table (passed/failed/skipped with error details)
```

To run a specific test file:
```text
Agent: subagent({ agent: "test-runner", task: "Запусти tests/basic.spec.ts и верни отчёт" })
```

To filter by name:
```text
Agent: subagent({ agent: "test-runner", task: "Запусти тесты с pattern 'login' через --grep" })
```

### test-fixer workflow

```text
User: тесты падают, почини
Agent: subagent({ agent: "test-fixer", task: "Запусти все e2e тесты, найди причины падений и исправь" })
Subagent: runs test → reads error output → fixes code → re-runs → returns final report
```

The fixer runs tests, analyzes failures, fixes the root cause (in test files or application code), re-runs, and confirms everything passes. If it needs more context about business logic, it reads `agents.md` and asks clarifying questions.

## Common Issues

- **`EADDRINUSE` on port 3001 (backend)**: Run `npm run kill:backend` (uses PID file) or find PID with `netstat -ano | grep :3001`
- **`EADDRINUSE` on port 3000 (frontend/Nuxt)**: Run `npm run kill:frontend` or find PID with `netstat -ano | grep :3000`
- **Frontend not built**: `npm run build:frontend` → `apps/frontend/.output/` (Nitro). Backend больше не раздаёт статику.
- **`/api` 404 в браузере**: Nuxt не проксирует — проверь `routeRules` в `nuxt.config.ts` и `NUXT_API_BASE`.
- **401 на /admin под SSR**: cookie не проксируется — проверь `useApi` (`useRequestHeaders(['cookie'])`).
- **CDP connection fails**: Chrome must be launched with `--remote-debugging-port=9222`
- **Tests can't navigate**: Use full URLs (not relative) — `baseURL` from config doesn't apply to CDP-connected pages
- **Check logs for errors**: `logs/backend.log` and `logs/frontend.log` — agent reads these; to start/stop a service, ask the user to run `npm run dev:*:log` / `npm run kill:*` (unless the user explicitly told you to do it)
