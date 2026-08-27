# Deployment

## Обзор

Приложение состоит из **двух отдельных сервисов** в Docker:

- **frontend** (Nuxt 3 SSR, Nitro-сервер) — порт **3000**, edge (за nginx-proxy).
  Рендерит публичную часть на сервере (SSR), проксирует `/api/**` → backend.
- **backend** (Nest.js API) — порт **3001**, внутренний (без `VIRTUAL_HOST`,
  порт наружу не проброшен). Чистый API на `/api`.
- **postgres** — внутренний (порт 5432 наружу не проброшен в prod).

Nuxt проксирует `/api/**` → `http://backend:3001` через `routeRules`
(цель из `NUXT_API_BASE`). Внешний трафик идёт только на frontend.

## Dockerfile (split, multi-stage)

- `docker/Dockerfile.frontend` — deps → `nuxt build` → production-образ
  (Nitro-сервер, `node .output/server/index.mjs`). Порт 3000, `NITRO_HOST=0.0.0.0`.
- `docker/Dockerfile.backend` — deps → `nest build` → production-образ
  (`node apps/backend/dist/main.js`). Порт 3001.
- Старый `docker/Dockerfile` (один образ, Nest раздавал статику) — **удалён**.

### Что копируется в production

| Источник | Путь в контейнере |
|----------|------------------|
| backend build | `apps/backend/dist/` (включая `dist/migrations/*.js`) |
| frontend build | `apps/frontend/.output/` (Nitro server + chunks) |

**Важно**: `apps/backend/.env` **не** копируется — env переопределяется через
`env_file` в docker-compose / `NUXT_*` env в frontend.

## Docker Compose

### Local / Dev (`docker-compose.yml`)

```bash
cd docker
docker compose up -d
```

Сервисы: `frontend` (3000:3000), `backend` (3001:3001), `postgres` (5432:5432).
Nuxt проксирует `/api` → `http://backend:3001/api`.

### Production (`docker-compose.prod.yml`)

```bash
cd docker
cp .env.example .env   # или рендерится ansible из templates/env.j2
docker compose -f docker-compose.prod.yml up -d --build
```

- `frontend` — `VIRTUAL_HOST`/`LETSENCRYPT_*`, сеть `reverse-proxy`, порт 3000.
- `backend` — без `VIRTUAL_HOST`, без проброса порта, внутренняя сеть.
- `postgres` — без проброса 5432.

### E2E tests (`docker-compose.e2e.yml`)

```bash
cd docker
docker compose -f docker-compose.e2e.yml up e2e
# Playwright UI: http://localhost:8080
```

## Переменные окружения

### Backend (`docker/env`, prod)

| Variable | Default | Описание |
|----------|---------|----------|
| `PORT` | `3001` | Backend (внутренний API) |
| `CORS_ORIGIN` | `https://<domain>` | Allowed origins (домен за nginx-proxy) |
| `COOKIE_SECURE` | `true` | Cookie-auth: secure в проде (HTTPS) |
| `JWT_SECRET` | (required) | **Изменить в production!** |
| `DB_TYPE` | `postgres` | `sqlite` or `postgres` |
| `DB_SYNCHRONIZE` | `false` | `false` = migrations (prod) |
| `DB_HOST` | `postgres` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USERNAME` | `<project_name>` | PostgreSQL user (выводится из project_name) |
| `DB_DATABASE` | `<project_name>_db` | PostgreSQL database |
| `DB_PASSWORD` | (secret) | PostgreSQL password |
| `ADMIN_LOGIN` | `admin` | First admin (empty DB only) |
| `ADMIN_PASSWORD` | (required) | First admin password |
| `BRAND_TITLE` | `VibeSetup UI` | Брендинг (публичный) |
| `BRAND_FAVICON_URL` | `/favicon.svg` | Favicon URL |
| `VIRTUAL_HOST` | `<domain>` | nginx-proxy host (frontend) |
| `LETSENCRYPT_HOST` | `<domain>` | Let's Encrypt host |
| `LETSENCRYPT_EMAIL` | (required) | Let's Encrypt email |
| `S3_*` | (empty) | S3 storage (см. AGENTS.md) |

### Frontend (Nuxt runtime config)

| Variable | Контекст | Default | Описание |
|----------|----------|---------|----------|
| `NUXT_PUBLIC_API_BASE` | client | `/api` | Клиентский base (через Nitro прокси) |
| `NUXT_API_BASE` | server (SSR) | `http://backend:3001/api` | Серверный base (прямой fetch к backend) |
| `NITRO_HOST` | server | `0.0.0.0` | Nitro bind host |
| `NITRO_PORT` | server | `3000` | Nitro port |

Чтобы вынести frontend на отдельный сервер — сменить `NUXT_API_BASE` на публичный
URL backend (без правок кода).

### Backend dev (`apps/backend/.env`)

| Variable | Default | Описание |
|----------|---------|----------|
| `PORT` | `3001` | Backend (внутренний API) |
| `CORS_ORIGIN` | `http://localhost:3000` | Nuxt-origin (dev) |
| `DB_TYPE` | `sqlite` | SQLite или PostgreSQL |
| `DB_SQLITE_PATH` | `./data/database.sqlite` | SQLite file path |
| `JWT_SECRET` | `dev-secret-change-me` | JWT secret |
| `ADMIN_LOGIN` | `admin` | First admin (empty DB only) |
| `COOKIE_SECURE` | (empty) | Cookie secure (auto в проде) |

### .env.local

`.env.local` (не под git) переопределяет `.env` (`override: true`) — сюда кладут
локальные креды S3/MinIO. Шаблон: `apps/backend/.env.local.example`. Внешнее
окружение (прод-контейнер) имеет наивысший приоритет. Загрузчик:
`apps/backend/src/env.ts`. Полный список `S3_*` — в корневом `AGENTS.md`.

## Порты

| Порт | Сервис | Доступ |
|------|--------|--------|
| 3000 | frontend (Nuxt SSR, edge) | Внешний (за nginx-proxy) / `localhost:3000` (dev) |
| 3001 | backend (Nest API, внутренний) | Внутренний (docker network) / `localhost:3001` (dev) |
| 80   | HTTP (nginx-proxy) | Внешний |
| 443  | HTTPS (nginx-proxy) | Внешний |
| 5432 | PostgreSQL | Внутренний (Docker) / `localhost:5432` (dev) |
| 9222 | Chrome CDP | Только e2e |
| 8080 | Playwright UI | Только e2e Docker |

## Деплой через deploy.sh / ansible

`deploy.sh` (корень) читает корневой `.env` (SSH, DOMAIN, PROJECT_NAME, бренд,
admin), sftp'ит архив на сервер, генерирует `.app.secrets` (db_password, jwt_secret)
и запускает `ansible-playbook`. Ansible ставит Docker, поднимает nginx-proxy +
acme-companion, собирает и поднимает frontend+backend+postgres.

Полная инструкция — в [`ansible/README.md`](../ansible/README.md) и
[`deploy.sh`](../deploy.sh).

### Портируемость по форкам

- `PROJECT_NAME` — **обязателен** в `.env` (нет дефолта, нет хардкода).
- `project_dir`/`archive_path`/`db_username`/`db_name` выводятся из `project_name`.
- `group_vars/all.yml` — плейсхолдеры/выводимые; реальные значения — в `vars.yml`.
- Проверка: `grep -rn "gmoreva-setup\|vibesetup_db\|/opt/vibesetup" deploy.sh ansible/ docker/ .env.example`
  — только плейсхолдеры/комментарии.

### Краткие шаги

1. Заполнить корневой `.env` (SSH_*, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD,
   PROJECT_NAME, BRAND_*).
2. `./deploy.sh` — собирает архив, sftp, генерация секретов, ansible-playbook.
3. Healthcheck: `https://<DOMAIN>/api/users/count` → 200.

### nginx-proxy (мульти-проект)

Общий `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion` поднимаются один раз
на сервере (тег `proxy`). Каждый проект-контейнер подключается к external-сети
`reverse-proxy` и объявляет `VIRTUAL_HOST`/`LETSENCRYPT_HOST`/`LETSENCRYPT_EMAIL`.

## Частые ошибки

1. **JWT-secret по дефолту** — замените `dev-secret-change-me` на production-ключ.
2. **CORS blocked** — `CORS_ORIGIN` backend должен включать домен (prod) /
   `http://localhost:3000` (dev). SSR-фетч идёт мимо CORS.
3. **Backend не стартует** — проверьте `docker compose logs backend`; частая
   причина — PostgreSQL ещё не готов (`depends_on` / healthcheck).
4. **`/api` 404 на клиенте** — Nuxt не проксирует: проверьте `routeRules` в
   `nuxt.config.ts` и `NUXT_API_BASE`.
5. **401 на /admin под SSR** — cookie не проксируется: проверьте `useApi`
   (`useRequestHeaders(['cookie'])`).
6. **Cookie не ставится** — `COOKIE_SECURE=true` требует HTTPS; в dev оставьте
   пустым/false.

## Чек-лист деплоя

- [ ] nginx-proxy + acme-companion запущены, сеть `reverse-proxy` доступна
- [ ] `.env` (deploy.sh) заполнен: `PROJECT_NAME`, `DOMAIN`, `LETSENCRYPT_EMAIL`,
      `ADMIN_PASSWORD`, SSH-креды
- [ ] `JWT_SECRET` — production-ключ (генерируется в `.app.secrets`)
- [ ] `CORS_ORIGIN` = домен (рендерится ansible)
- [ ] `COOKIE_SECURE=true` (прод, HTTPS)
- [ ] `DB_SYNCHRONIZE=false` (prod — миграции при старте)
- [ ] Миграции накатываются (проверить `docker compose logs backend` — нет ошибок TypeORM)
- [ ] DNS-запись домена указывает на IP сервера
- [ ] `docker compose -p <project> -f docker-compose.prod.yml up -d --build` прошёл
- [ ] PostgreSQL healthcheck прошёл
- [ ] HTTPS-сертификат получен (acme-companion)
- [ ] `curl -I https://<DOMAIN>/` → 200 (frontend SSR)
- [ ] `curl https://<DOMAIN>/api/users/count` → 200 (прокси → backend)
- [ ] `curl https://<DOMAIN>/api/auth/me` → 401 (без cookie)