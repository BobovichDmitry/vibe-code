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

В dev (без Docker) порт frontend (`PORT`, влияет только на `nuxt dev`) и
`NUXT_API_BASE` задаются в `apps/frontend/.env` / `.env.local` (грузится в
`nuxt.config.ts` через dotenv). `NITRO_HOST`/`NITRO_PORT` выше — только прод
(Nitro в контейнере).

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

> **Смена порта в dev**: задайте `PORT` в `apps/backend/.env.local` (шаблон
> `.env.local.example` содержит секцию про PORT) — без правок кода. При смене
> порта backend обновите также `NUXT_API_BASE` у frontend (и `CORS_ORIGIN`).

### .env.local (dev, оба сервиса)

`.env.local` (не под git) переопределяет `.env` — порты и локальные креды S3/MinIO.
Есть у **обоих сервисов**: `apps/backend/.env.local.example` (PORT, S3_*;
загрузчик `apps/backend/src/env.ts`, `override: true`) и `apps/frontend/.env.local.example`
(PORT, NUXT_*; грузится в `nuxt.config.ts` через dotenv). Внешнее окружение
(прод-контейнер) имеет наивысший приоритет. При смене порта backend обновите
`NUXT_API_BASE` у frontend (и `CORS_ORIGIN` у backend). Полный список `S3_*` —
в корневом `AGENTS.md`.

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

В dev порты 3000/3001 переопределяются через `PORT` в `apps/<service>/.env.local` (у frontend — только для `nuxt dev`; в проде порт задаёт `NITRO_PORT`, backend в docker — `PORT` из compose-env).

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

## Деплой через GitLab CI (автоматический)

Пайплайн [`.gitlab-ci.yml`](../.gitlab-ci.yml): этапы **build → deploy**. На push
в `master` обе джобы `deploy:test` и `deploy:production` запускаются **автоматом**
(перевести прод в manual — правка одной строки `when` в rules джобы).

- **`build:docker`** — собирает и пушит оба образа в Registry
  (`$CI_REGISTRY_IMAGE/{frontend,backend}`) с тегами `$CI_COMMIT_SHORT_SHA` +
  `$CI_COMMIT_REF_SLUG`; на default-ветке дополнительно тег `latest`.
- **`deploy:test` / `deploy:production`** — деплой из Registry **без сборки на
  сервере**: каждая джоба берёт ОДНУ переменную окружения и запускает
  [`docker/deploy_ci.sh`](../docker/deploy_ci.sh). `resource_group` на каждой
  джобе защищает от параллельных деплоев одного окружения.

### Бандл-переменные (Settings → CI/CD → Variables, флаги protected + masked)

| Variable | Окружение |
|----------|-----------|
| `DEPLOY_BUNDLE_TEST` | тест-сервер |
| `DEPLOY_BUNDLE_PRODUCTION` | прод-сервер |

Каждая переменная — **base64-бандл** `base64(tar.gz[id_rsa, .env])`:

- `id_rsa` — приватный SSH-ключ **без passphrase** (юзер с sudo на сервере);
- `.env` — тот же формат, что у `deploy.sh`: обязательные `SSH_HOST`, `SSH_USER`,
  `DOMAIN`, `LETSENCRYPT_EMAIL`, `ADMIN_PASSWORD`, `PROJECT_NAME`; опциональные
  `SSH_PORT`, `PROJECT_DIR`, `ARCHIVE_PATH`, `PROXY_DIR`, `BRAND_*`, `ADMIN_LOGIN`
  (`SSH_KEY` указывать не нужно — ключ берётся из бандла).

Старые переменные `DEPLOY_HOST` / `DEPLOY_PATH` / `SSH_PRIVATE_KEY` /
`DEPLOY_COMPOSE_PROJECT` больше **не используются**. Бандл содержит приватный
ключ — задавать только через GitLab Variables (protected + masked) или класть в
`./.ci-bundle` (в `.gitignore`, коммитить нельзя).

### Формирование бандла и локальный тест-запуск

```bash
# Формирует base64-строку в stdout → вставить в GitLab Variable ИЛИ в .ci-bundle:
scripts/make_deploy_bundle.sh <path/to/id_rsa> <path/to/.env> > .ci-bundle

# Тест-запуск без GitLab: CI_REGISTRY/CI_JOB_TOKEN не заданы → registry-логин
# скипается (считается, что docker login в registry на сервере сделан руками).
DEPLOY_BUNDLE="$(cat .ci-bundle)" \
FRONTEND_IMAGE="registry.example.com/proj/frontend:abc123" \
BACKEND_IMAGE="registry.example.com/proj/backend:abc123" \
  bash docker/deploy_ci.sh
```

`make_deploy_bundle.sh` предупреждает, если ключ с passphrase или в `.env` нет
обязательных переменных.

### Поток docker/deploy_ci.sh

1. Декодирует бандл (`DEPLOY_BUNDLE` из CI или `./.ci-bundle` для ручного запуска)
   → SSH-ключ + `.env`.
2. На **пустом** сервере ставит всё с нуля: ansible → docker (роль `deps`) →
   nginx-proxy + acme-companion (роль `proxy`); sftp'ит архив исходников +
   deploy-env.sh.
3. Генерирует `.app.secrets` (db_password, jwt_secret — один раз, при повторных
   деплоях переиспользуются) и `ansible/vars.yml`.
4. Логин в Registry **временным токеном** (`CI_JOB_TOKEN`, пароль через stdin;
   живёт только в рамках джобы), после деплоя — `docker logout`.
5. Запускает `ansible-playbook` с extra vars `frontend_image`/`backend_image` →
   роль `app` в **Registry-режиме**: прокидывает `FRONTEND_IMAGE`/`BACKEND_IMAGE`
   (теги по SHA) в `docker/.env` и делает `docker compose pull frontend backend`
   вместо build. Без этих vars — старый build-режим (ручной `deploy.sh` не менялся).
6. Healthcheck: `https://$DOMAIN/api/users/count` → 200.

### Требования и ограничения CI-деплоя

- **Бандл-переменная не задана → деплой пропускается**: джоба завершается успешно с
  warning'ом в консоли («деплой пропущен»), пайплайн остаётся зелёным. Чтобы деплой
  заработал — заведите `DEPLOY_BUNDLE_*` в Settings → CI/CD → Variables (protected+masked).
- Ветка `master` — **protected**: иначе protected-переменные недоступны и джоба
  пропустит деплой (а не упадёт) — бандл просто не будет виден на непротектед ветке.
- **Host key сервера**: по умолчанию `StrictHostKeyChecking=accept-new` — если сервер
  пересоздан и в known_hosts раннера остался старый ключ, деплой упадёт с
  `REMOTE HOST IDENTIFICATION HAS CHANGED`. Отключить проверку — переменная
  `DEPLOY_SKIP_HOST_KEY_CHECK=1` (Settings → CI/CD → Variables; НЕБЕЗОПАСНО — MITM-риск);
  безопасная альтернатива — `ssh-keygen -R <host>` на раннере.
- `CI_JOB_TOKEN` открывает только Registry **своего** проекта; для образов из
  чужого проекта нужен deploy token.
- Чек-лист: оба образа в Registry (тег SHA) → бандлы заведены (protected+masked,
  ветка protected) → DNS домена указывает на IP сервера → джобы зелёные →
  `curl https://<DOMAIN>/api/users/count` → 200.

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
7. **Deploy-джоба зелёная, но деплой пропущен (warning в логе)** — бандл-переменная
   (`DEPLOY_BUNDLE_TEST` / `DEPLOY_BUNDLE_PRODUCTION`) не заведена в
   Settings → CI/CD → Variables, или ветка не protected (protected-переменные
   недоступны на обычных ветках). Заведите бандл — и деплой включится
   на следующем пайплайне.
8. **`docker pull` 401/unauthorized на сервере** — Registry-логин не выполнен:
   при ручном тест-запуске `deploy_ci.sh` без `CI_REGISTRY`/`CI_JOB_TOKEN`
   авторизуйтесь в registry на сервере руками (`docker login`).

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