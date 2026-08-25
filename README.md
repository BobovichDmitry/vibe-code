# VibeSetup UI — Шаблон Nest.js + Vue 3 приложения

Стартовый каркас (скелет) для вайбкодинга: авторизация (JWT), админ-панель управления пользователями с вертикальным сайдбаром, публичная страница со счётчиком пользователей, двухрежимная БД (dev `synchronize` / prod миграции), Docker + ansible-деплой через nginx-proxy. Бизнес-механик нет — каркас готов к самостоятельной разработке.

> **🤖 Для AI-агентов**: для развёртывания через Node.js (без Docker) см. [readme-for-agents.md](readme-for-agents.md). Для деплоя через ansible — раздел [Деплой через ansible](#деплой-через-ansible) ниже.

## Структура

```
vibe-setup-ui/
├── apps/
│   ├── backend/          # Nest.js API (/api/auth, /api/users, /api/branding)
│   │   └── src/migrations/   # TypeORM-миграции (prod)
│   └── frontend/         # Vue 3 + Tailwind (SPA, hash-router)
├── ansible/              # Ansible-деплой НА сервере (Docker + nginx-proxy)
├── e2e/                  # Playwright e2e (CDP / headless / API-only)
├── docker/               # Dockerfile + docker-compose (+ prod.yml)
├── docs/                 # Документация
├── scripts/              # log-runner, kill-service
├── tasks/                # Очередь задач (см. tasks/agents.md)
└── package.json          # Root workspace (npm workspaces)
```

## Быстрый старт (локальная разработка)

```bash
# 1. Установка зависимостей
npm install

# 2. Запуск dev-серверов (backend :3000, frontend :5173)
npm run dev

# Отдельные команды с логированием (PID в logs/*.pid):
npm run dev:backend:log    # Backend → logs/backend.log
npm run dev:frontend:log   # Frontend → logs/frontend.log

# Остановка сервисов (по PID-файлу):
npm run kill:backend
npm run kill:frontend
```

Логи ротируются на 10 МБ: `backend.log` → `backend.1.log` → … → `backend.5.log`.

Первый админ создаётся автоматически на пустой БД из `ADMIN_LOGIN`/`ADMIN_PASSWORD` (см. `apps/backend/.env`). Дефолт: `admin` / `admin` — **смените перед продом**.

## База данных — два режима

Режим переключается одной переменной `DB_SYNCHRONIZE`:

| Режим | `DB_SYNCHRONIZE` | Поведение | Где |
|-------|------------------|-----------|-----|
| **Dev** | `true` (дефолт) | `synchronize: true` — TypeORM сам приводит схему под сущности. Миграции не запускаются. | Локальная разработка, e2e |
| **Prod** | `false` | `synchronize: false`, `migrationsRun: true` — при старте Nest накатывает pending-миграции. | Production |

- **Локально — SQLite** (`apps/backend/.env`: `DB_TYPE=sqlite`, `DB_SQLITE_PATH=./data/database.sqlite`).
- **Прод — PostgreSQL** (`DB_TYPE=postgres` + `DB_HOST`/`DB_PORT`/...).

### Команды миграций (для prod-разработки)

```bash
npm run migration:generate -- apps/backend/src/migrations/MyChange  # сгенерировать по дрифту
npm run migration:create   -- apps/backend/src/migrations/MyChange  # пустой шаблон
npm run migration:run        # применить pending-миграции
npm run migration:revert     # откатить последнюю
npm run db:recreate           # дроп схемы + накат миграций с нуля (prod-prep, не на dev-SQLite)
npm run db:reset              # dev-утилита (synchronize): дроп + пересоздание
npm run create-admin          # создать админа (CLI)
```

> Целевой прод-диалект — PostgreSQL. Перед релизом проверьте отсутствие дрейфа: `db:recreate` (на postgres) → `migration:generate` должен сообщить «No changes». Подробно — [docs/migrations.md](docs/migrations.md).

### Добавить изменение схемы

1. Правите entity. 2. `npm run migration:generate -- apps/backend/src/migrations/AddFoo`. 3. Ревьюите сгенерированный файл (диалект-агностичность, data-migration в `up()`/`down()`). 4. Проверяете prod-prep цикл. 5. Коммитите entity + миграцию вместе.

## Сборка и продакшн (локально)

```bash
npm run build           # frontend → dist, backend → dist (миграции попадают в dist/migrations/)
npm run start:prod      # production (Nest сервит статичный фронтенд)
```

## Docker

```bash
# Dev-профиль (app + PostgreSQL, порт 5432 наружу для удобства):
cd docker && docker compose up -d

# Production-профиль (без проброса БД, для nginx-proxy):
cd docker && docker compose -f docker-compose.prod.yml up -d
```

`docker-compose.prod.yml`: app + postgres, `5432` **не** наружу, external-сеть `reverse-proxy`, `VIRTUAL_HOST`/`LETSENCRYPT_HOST` из env, `DB_SYNCHRONIZE=false`. Используется ansible (см. ниже).

Переменные прод-окружения — `docker/env` / `docker/.env.example`:

```
DB_TYPE=postgres
DB_HOST=postgres
DB_SYNCHRONIZE=false        # prod — миграции
JWT_SECRET=<сгенерировать>
ADMIN_LOGIN=admin
ADMIN_PASSWORD=<сильный пароль>
BRAND_TITLE=VibeSetup UI
BRAND_FAVICON_URL=/favicon.svg
VIRTUAL_HOST=app.example.com
LETSENCRYPT_HOST=app.example.com
LETSENCRYPT_EMAIL=devops@example.com
CORS_ORIGIN=https://app.example.com
```

## Деплой через ansible

Ansible **запускается на целевом сервере** (`ansible_connection=local`), не на ПК разработчика. Разработчик только собирает архив исходников и передаёт его на сервер по sftp. Ansible ставит Docker/compose, поднимает общий nginx-proxy + Let's Encrypt, распаковывает архив, собирает и запускает приложение. Переменные: `server_ip`, `domain` и др.

```bash
# Шаг 1 (на ПК): собрать архив исходников
cd vibe-setup-ui
tar --exclude=node_modules --exclude=dist --exclude=logs --exclude=data \
    --exclude=.git --exclude=playwright-report --exclude=test-results \
    -czf vibesetup.tar.gz .

# Шаг  2 (на ПК): передать по sftp
sftp root@<server_ip>
sftp> put vibesetup.tar.gz /opt/
sftp> exit

# Шаг 3 (на сервере): запустить ansible
ssh root@<server_ip>
apt update && apt install -y ansible
cd /opt/vibesetup/ansible
cp vars.example.yml vars.yml        # заполнить: domain, db_password, jwt_secret, admin_password, letsencrypt_email
ansible-vault encrypt vars.yml       # секреты — обязательно в vault
ansible-playbook playbook.yml -e @vars.yml
```

Теги: `deps` (Docker), `proxy` (nginx-proxy+acme, один раз на сервере), `deploy` (приложение), `healthcheck`. Мульти-проект: nginx-proxy общий, каждый проект подключается к external-сети `reverse-proxy` со своим `VIRTUAL_HOST`. Полная инструкция — [ansible/README.md](ansible/README.md).

## E2E-тесты

Тесты на Playwright. Режим браузера управляется env (`e2e/.env`):

| `E2E_USE_BROWSER` | `E2E_HEADLESS` | Режим |
|-------------------|----------------|-------|
| `true` (дефолт) | `false` (дефолт) | CDP — `connectOverCDP` к Chrome на `--remote-debugging-port=9222` |
| `true` | `true` | Playwright `chromium.launch({ headless: true })` (без внешнего Chrome) |
| `false` | — | API-only (axios против `E2E_API_URL`, браузер не поднимается) |

```bash
# CDP-режим: сначала Chrome с remote debugging
chrome.exe --remote-debugging-port=9222

# Запуск
npm run test:e2e
npm run test:e2e -- e2e/tests/basic.spec.ts   # один файл
npm run test:e2e:ui                            # UI mode
```

## Переменные окружения (backend `apps/backend/.env`)

| Переменная | Дефолт | Описание |
|------------|--------|----------|
| `DB_TYPE` | `sqlite` | `sqlite` или `postgres` |
| `DB_SYNCHRONIZE` | `true` | `true` — dev (synchronize), `false` — prod (миграции) |
| `DB_SQLITE_PATH` | `./data/database.sqlite` | Путь SQLite |
| `DB_HOST`/`DB_PORT`/`DB_USERNAME`/`DB_PASSWORD`/`DB_DATABASE` | — | PostgreSQL |
| `PORT` | `3000` | Порт backend |
| `JWT_SECRET` | `dev-secret-change-me` | **Сменить на проде!** |
| `ADMIN_LOGIN` / `ADMIN_PASSWORD` | `admin` / `admin` | Первый админ (только на пустой БД) |
| `BRAND_TITLE` | `VibeSetup UI` | Название продукта (`GET /api/branding`) |
| `BRAND_FAVICON_URL` | `/favicon.svg` | Favicon (`GET /api/branding`) |
| `CORS_ORIGIN` | `http://localhost:5173,...` | Разрешённые CORS-источники |

## API

| Метод | Endpoint | Описание |
|-------|----------|----------|
| POST | `/api/auth/login` | Авторизация → `{ access_token }` |
| GET | `/api/auth/me` | Текущий пользователь (JWT) |
| PATCH | `/api/auth/password` | Смена пароля (JWT) |
| GET | `/api/users` | Все пользователи (admin) |
| GET | `/api/users/:id` | Один пользователь (admin) |
| POST | `/api/users` | Создать пользователя (admin) |
| PATCH | `/api/users/:id` | Обновить пользователя (admin) |
| DELETE | `/api/users/:id` | Удалить пользователя (admin) |
| GET | `/api/users/count` | Количество пользователей (**публичный**) |
| GET | `/api/branding` | Бренд: `{ title, faviconUrl }` (**публичный**, из env) |

## Удалённый доступ к серверу (SSH/SFTP через MCP)

Для работы с целевым сервером прямо из pi-агента настроен MCP-сервер в [`.pi/mcp.json`](.pi/mcp.json):

- **`ssh-connect`** — SSH + SFTP (выполнение команд и передача файлов на сервере), `npx ssh-mcp` → [scripts/ssh.sh](scripts/ssh.sh)

Скрипт читает SSH-доступы из корневого `.env` (не в git). Достаточно создать его из примера и заполнить:

```bash
cp .env.example .env
# заполнить: SSH_HOST (домен или IP), SSH_USER и один из способов аутентификации
```

**Вариативная аутентификация** — ключ приоритетнее пароля:

```bash
# Вариант 1 — по ключу (если ключ запаролен — указать SSH_KEY_PASSPHRASE):
SSH_HOST=app.example.com
SSH_USER=root
SSH_KEY=~/.ssh/id_ed25519          # на Windows: C:/Users/you/.ssh/id_ed25519
SSH_KEY_PASSPHRASE=********         # опционально, только для запароленного ключа

# Вариант 2 — по паролю (если SSH_KEY не задан):
SSH_HOST=app.example.com
SSH_USER=root
SSH_PASSWORD=********
```

После этого инструменты `ssh-connect` (включая SFTP-операции `sftp-upload`/`sftp-download`) доступны агенту — можно выполнять команды на сервере и передавать файлы без ручного SSH. Пакет `ssh-mcp` v2 подтягивается через `npx` автоматически.

> **ssh-mcp v2:** секреты только через env (v2 убрал `--password` CLI). Скрипт маппит `SSH_PASSWORD` → `SSH_MCP_PASSWORD` (auth=password) и `SSH_KEY_PASSPHRASE` → `SSH_MCP_PASSPHRASE` (auth=key, запароленный ключ); путь ключа передаётся через `--key`. Approval-гейт отключён (`--disableApproval`) для автономной работы агента (pi MCP-адаптер не поддерживает elicitation); policy-engine и forbidden-list (`rm -rf /` и т.п.) всё равно действуют.
>
> Для SSH agent (auth=agent, `SSH_AUTH_SOCK`) используйте TOML-конфиг ssh-mcp. Для non-root пользователя с sudo — добавьте `--group=dev` в `scripts/ssh.sh` (иначе `privileged-command` запрещён на prod-tier).

## Очередь задач (tasks/)

Проект использует очередь задач в `tasks/` (см. [tasks/agents.md](tasks/agents.md)) — источник истины `tasks/index.md` (разделы Todo/NeedInfo/Errors/Done). Скиллы: `task-creator`, `task-solver`, `task-batch-solver`, `task-list-converter`; сабагенты: `code-solver`, `e2e-writer`, `docs-maintainer`, `test-runner`, `test-fixer`, `browser-checker`.

## Документация

- [GETTING_STARTED.md](docs/GETTING_STARTED.md) — запуск с нуля
- [deployment.md](docs/deployment.md) — деплой, переменные, порты
- [migrations.md](docs/migrations.md) — двухрежимная БД, миграции, prod-prep цикл
- [testing-guide.md](docs/testing-guide.md) — тестирование
- [ansible/README.md](ansible/README.md) — ansible-деплой на сервере
- [areas/backend-api-structure.md](docs/areas/backend-api-structure.md) · [frontend-structure.md](docs/areas/frontend-structure.md) · [database-structure.md](docs/areas/database-structure.md) · [auth-structure.md](docs/areas/auth-structure.md) · [admin-panel.md](docs/areas/admin-panel.md)