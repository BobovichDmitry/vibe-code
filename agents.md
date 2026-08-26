# VibeSetup UI — Agent Guide

## Architecture

**Monorepo** (npm workspaces) with Nest.js backend, Vue.js frontend, Playwright e2e tests. Single Docker container in production — frontend built into Nest.js static.

```
vibe-setup-ui/
├── apps/
│   ├── backend/          # Nest.js API (/api/auth, /api/users)
│   │   ├── src/
│   │   │   ├── main.ts                 # Entry, global prefix 'api', SPA serve
│   │   │   ├── app.module.ts           # Root module, seeds DB on startup
│   │   │   ├── database/               # SQLite/PostgreSQL TypeORM config
│   │   │   ├── auth/                   # JWT auth (login, me, password)
│   │   │   │   ├── entities/admin.entity.ts
│   │   │   │   ├── auth.controller.ts
│   │   │   │   ├── auth.service.ts
│   │   │   │   ├── jwt.strategy.ts
│   │   │   │   └── jwt-auth.guard.ts
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
│   │   └── .env                        # DB_TYPE, DB_* settings, PORT, S3_*
│   └── frontend/         # Vue 3 + Tailwind (SPA)
│       ├── src/
│       │   ├── api/auth.ts              # Axios client for auth
│       │   ├── api/users.ts             # Axios client for users
│       │   ├── api/files.ts             # Axios client for files (S3)
│       │   ├── components/              # Shared components
│       │   ├── views/PublicView.vue     # Public page (user count)
│       │   ├── views/LoginView.vue      # Login form
│       │   ├── views/admin/ManageUsersView.vue  # Users CRUD
│       │   ├── views/admin/ManageFilesView.vue  # Files (S3) CRUD
│       │   ├── layouts/AdminLayout.vue  # Admin layout (sidebar: Users + Files)
│       │   ├── router/index.ts          # Hash router
│       │   ├── composables/useAuth.ts   # Auth state
│       │   └── style.css                # Tailwind directives
│       ├── vite.config.ts               # proxy /api → localhost:3000
│       └── .env                         # VITE_API_BASE_URL=/
├── e2e/                    # Playwright e2e tests (remote Chrome CDP)
│   ├── fixtures.ts          # test.extend: connectedBrowser, connectedPage
│   ├── global-setup.ts      # Checks Chrome CDP, seeds DB via API
│   ├── tests/basic.spec.ts  # Login → create user → check count
│   ├── playwright.config.ts
│   └── .env                 # BROWSER_PORT, REMOTE_CHROME_HOST, E2E_*
├── docker/
│   ├── Dockerfile           # Multi-stage: frontend build → backend build → prod
│   ├── docker-compose.yml   # Dev: App + PostgreSQL (5432 exposed)
│   ├── docker-compose.prod.yml  # Prod: App + PostgreSQL (5432 NOT exposed, reverse-proxy network)
│   ├── docker-compose.e2e.yml  # E2E tests with Playwright UI (:8080)
│   ├── docker-compose.nginx-proxy.yml  # Prod with nginx-proxy + Let's Encrypt (legacy variant)
│   └── env                  # Production env template
├── ansible/                # Ansible-деплой (запуск НА сервере)
│   ├── ansible.cfg          # inventory, host_key_checking=False
│   ├── inventory.ini        # localhost, ansible_connection=local
│   ├── group_vars/all.yml   # Переменные (плейсхолдеры)
│   ├── vars.example.yml     # Пример заполнения переменных
│   ├── playbook.yml         # Основной плейбук (tags: deps, proxy, deploy, healthcheck)
│   ├── roles/               # docker, nginx_proxy, app
│   ├── templates/           # env.j2, compose-proxy.yml.j2
│   └── README.md            # Инструкция: sftp архива + запуск на сервере
├── docs/                   # Documentation
│   ├── GETTING_STARTED.md   # Full setup guide (Docker, nginx-proxy, local)
│   ├── deployment.md        # Deploy, env vars, ports, checklists
│   ├── testing-guide.md     # Testing guide
│   ├── agents.md            # Agent quick reference
│   ├── project-overview.md  # Architecture overview
│   ├── context-index.md     # Doc index
│   └── areas/               # Area-specific docs
│       ├── backend-api-structure.md
│       ├── auth-structure.md
│       ├── database-structure.md
│       ├── frontend-structure.md
│       ├── admin-panel.md
│       └── e2e-testing-structure.md
├── scripts/
│   ├── log-runner.mjs       # Runs service with logging to logs/<name>.log
│   └── kill-service.mjs     # Kills service by PID file
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
- `logs/backend.pid` / `logs/frontend.pid` — process IDs (if present, the service is running)

### Build & Prod

| Command | Description |
|---------|-------------|
| `npm install` | Install all workspace deps |
| `npm run build:frontend` | Build Vue → `apps/frontend/dist/` |
| `npm run build:backend` | Build Nest → `apps/backend/dist/` |
| `npm run build` | Both builds |
| `npm run start:prod` | Production (Nest serves static frontend) |
| `npm run test:e2e` | Run Playwright tests against running app |
| `npm run db:reset` | Reset DB (dev: drop + synchronize) |
| `npm run db:recreate` | Recreate DB (prod-prep: drop + миграции) |
| `npm run migration:run` | Накатить pending-миграции (TypeORM CLI) |
| `npm run migration:revert` | Откатить последнюю миграцию |
| `npm run migration:generate -- src/migrations/Name` | Сгенерировать миграцию из diff |

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
| `PORT` | `3000` | Backend port |
| `JWT_SECRET` | `dev-secret-change-me` | **Change in production!** |
| `ADMIN_LOGIN` | `admin` | First admin (empty DB only) |
| `ADMIN_PASSWORD` | `admin` | First admin (empty DB only) |
| `CORS_ORIGIN` | `http://localhost:5173,...` | CORS allowed origins |
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
| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_BASE_URL` | `/` | API base URL (proxy in dev, same-origin in prod) |

### E2E (`e2e/.env`)
| Variable | Default | Description |
|----------|---------|-------------|
| `BROWSER_PORT` | `9222` | Chrome remote debugging port |
| `REMOTE_CHROME_HOST` | `localhost` | Chrome host for CDP |
| `E2E_BASE_URL` | `http://localhost:5173` | App URL (dev frontend port) |
| `E2E_API_URL` | `http://localhost:3000/api` | API URL for seeding |

**REMOTE_DEBUGGING_URL** is derived: `http://${REMOTE_CHROME_HOST}:${BROWSER_PORT}`

## Key Design Decisions

1. **Single container**: Frontend is built into `apps/frontend/dist/` and served by Nest.js static middleware. SPA fallback sends `index.html` for non-API routes.

2. **API prefix**: `setGlobalPrefix('api')` + `@Controller('auth')` / `@Controller('users')` — all API routes at `/api/*`.

3. **Database abstraction**: Two connectors (SQLite/PostgreSQL) via `DB_TYPE` env. Two modes: dev uses `synchronize: true` (fast iteration), prod uses migrations (`DB_SYNCHRONIZE=false` → `migrationsRun: true`, auto-run pending at startup). SQLite for local/dev, PostgreSQL for production. Baseline migration (`InitSchema`) creates the full schema in one migration. TypeORM CLI scripts: `migration:generate/run/revert`, `db:recreate`.

4. **E2E via CDP**: Tests connect to an already-running Chrome via `connectOverCDP`. No headless browser — tests run in your actual browser. Launch Chrome with `--remote-debugging-port=9222`.

5. **Playwright fixtures**: Custom `connectedBrowser` and `connectedPage` fixtures manage the CDP connection. Pages ARE closed after each test to keep the browser clean.

6. **JWT Auth**: Bearer token, 24h expiry. Guard `@UseGuards(JwtAuthGuard)` for protected routes.

7. **Role-based access**: Roles `admin` and `user`. Only `admin` can CRUD users.

8. **Hash router**: Vue uses `createWebHashHistory` to avoid server-side route config for SPA.

9. **Seeding**: First admin created automatically on empty DB (from `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars).

## API Endpoints

### Auth

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/login` | Login → `{ access_token }` |
| GET | `/api/auth/me` | Current user (JWT required) |
| PATCH | `/api/auth/password` | Change password (JWT required) |

### Users

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/users` | All users (admin only) |
| GET | `/api/users/:id` | Single user (admin only) |
| POST | `/api/users` | Create user (admin only) |
| PATCH | `/api/users/:id` | Update user (admin only) |
| DELETE | `/api/users/:id` | Delete user (admin only) |
| GET | `/api/users/count` | User count (public, no auth) |

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
# Dev (single container)
cd docker && docker compose up -d

# Production via ansible (запуск НА сервере — см. ansible/README.md)
# Ansible ставит Docker, поднимает nginx-proxy, собирает и поднимает приложение
ansible-playbook playbook.yml -e @vars.yml

# E2E tests (Playwright UI on :8080)
cd docker && docker compose -f docker-compose.e2e.yml up e2e
```

- **`docker-compose.yml`** (dev): app + PostgreSQL, порт `5432` проброшен наружу.
- **`docker-compose.prod.yml`** (prod): app + PostgreSQL, `5432` **не** проброшен,
  external-сеть `reverse-proxy` (nginx-proxy), `VIRTUAL_HOST`/`LETSENCRYPT_*`.
  Используется ansible-плейбуком. Сборка — на сервере внутри Docker (multi-stage Dockerfile).
- **nginx-proxy** (`nginxproxy/nginx-proxy` + `nginxproxy/acme-companion`):
  общий reverse-proxy один раз на сервере (тег `proxy`). Мульти-проект —
  каждый контейнер подключается к `reverse-proxy` и объявляет свой `VIRTUAL_HOST`.

Dockerfile is multi-stage:
1. **frontend-builder**: Install frontend deps, `npm run build:frontend`
2. **backend-builder**: Install backend deps, `npm run build:backend`
3. **production**: Only prod deps + built artifacts from stages 1-2

## Writing E2E Tests

Tests import from `../fixtures` (NOT from `@playwright/test` directly):

```typescript
import { test, expect } from '../fixtures';
const BASE_URL = process.env.E2E_BASE_URL || 'http://localhost:5173';
const API_URL = process.env.E2E_API_URL || 'http://localhost:3000/api';

test('example', async ({ connectedPage }) => {
  await connectedPage.goto(`${BASE_URL}/`);
  // Use full URLs — baseURL doesn't apply with CDP connected pages
  expect(await connectedPage.locator('h1').first().textContent()).toContain('VibeSetup UI');
});
```

You do not need to run e2e test after every change. Only when user asks you

## Browser Work: Delegate to Subagent

**NEVER call `chrome_devtools_*` tools directly.** All browser work (navigation, screenshots, DOM inspection, console logs, network requests, performance tracing) MUST be delegated to the `browser-checker` subagent via the `subagent` tool.

```typescript
// ✅ Correct — delegate to subagent
subagent({
  agent: "browser-checker",
  task: "Navigate to http://localhost:5173 and take a screenshot"
})

// ❌ WRONG — never call chrome_devtools_* directly
chrome_devtools_navigate_page({ url: "http://localhost:5173" })
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
Agent: subagent({ agent: "browser-checker", task: "Navigate to http://localhost:5173, take screenshot of public page" })
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

- **`EADDRINUSE` on port 3000**: Run `npm run kill:backend` (uses PID file) or find PID with `netstat -ano | grep :3000`
- **Frontend not served**: Must run `npm run build:frontend` first. Backend auto-detects `../frontend/dist`.
- **CDP connection fails**: Chrome must be launched with `--remote-debugging-port=9222`
- **Tests can't navigate**: Use full URLs (not relative) — `baseURL` from config doesn't apply to CDP-connected pages
- **Check logs for errors**: `logs/backend.log` and `logs/frontend.log` — agent reads these; to start/stop a service, ask the user to run `npm run dev:*:log` / `npm run kill:*` (unless the user explicitly told you to do it)
