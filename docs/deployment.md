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
  (`node apps/backend/dist/main.js`). Порт 3001. В prod-этап добавлен **ffmpeg**
  (`apk add --no-cache ffmpeg`) — обработка медиа в проде (в dev используется
  системный ffmpeg).
- `docker/Dockerfile.ci-deploy` — образ для CI-деплой-джоб (ubuntu:24.04 +
  предустановленные `sops`, `yq`, `ssh`; `linux/amd64` + `linux/arm64`).
  Собирается джобой `build:ci-image` и пушится как
  `$CI_REGISTRY_IMAGE/ci-deploy:latest` — деплой-джобы не качают бинарники
  по сети при каждом запуске.
- Старый `docker/Dockerfile` (один образ, Nest раздавал статику) — **удалён**.

### Что копируется в production

Backend: `apps/backend/dist/` (включая `dist/migrations/*.js`);
frontend: `apps/frontend/.output/` (Nitro server + chunks).
**Важно**: `apps/backend/.env` **не** копируется — env задаётся через
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

При старте backend сам создаёт `DB_DATABASE`, если её нет (нужно право
`CREATEDB` у `DB_USERNAME`; в шаблоне `POSTGRES_USER` — superuser).
См. `docs/areas/database-structure.md`.

### E2E tests (`docker-compose.e2e.yml`)

```bash
cd docker
docker compose -f docker-compose.e2e.yml up e2e
# Playwright UI: http://localhost:8080
```

### Локальный MinIO (dev-тестирование S3) (`docker-compose.minio.yml`)

```bash
docker compose -f docker/docker-compose.minio.yml up -d
```

S3-совместимое хранилище для локальной разработки: **API** `http://localhost:9000`,
**консоль** `http://localhost:9001` (`minioadmin` / `minioadmin123`).
Креды подставьте в `apps/backend/.env.local` (`S3_ENDPOINT=http://localhost:9000`,
`S3_ACCESS_KEY=minioadmin`, `S3_SECRET_KEY=minioadmin123`, `S3_FORCE_PATH_STYLE=true`).

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

Любые **другие** переменные (все `S3_*`, `PUBLIC_BASE_URL`, `MOCK_TELEGRAM_POST_URL`
и любые переменные форка) попадают в `docker/env` через **generic pass-through** —
см. следующий раздел.

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
Есть у **обоих сервисов**: `apps/backend/.env.local.example` (PORT, S3_*) и
`apps/frontend/.env.local.example` (PORT, NUXT_*). Внешнее окружение
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
admin), sftp'ит архив на сервер, генерирует `.app.secrets` (db_password,
jwt_secret) и запускает `ansible-playbook`. Ansible ставит Docker, поднимает
nginx-proxy + acme-companion, собирает и поднимает frontend+backend+postgres.

### SSH-ключ без tty (CI/агент)

Если деплой запускается без терминала (CI, агент), а у SSH-ключа есть passphrase:
при заданном `SSH_KEY_PASSPHRASE` в `.env` `deploy.sh` поднимает локальный
`ssh-agent` + `SSH_ASKPASS` и добавляет ключ без tty; trap на выходе гасит
агент. Интерактивный ввод остаётся fallback'ом при наличии tty.

### Generic pass-through переменных окружения (extra_env)

**Любая** переменная, заданная форком в деплой-источниках, автоматически
попадает в `docker/env` на сервере как `KEY=value`. Править деплой-скрипты
или ansible-шаблоны не нужно. Пример: форк добавляет `YOOKASSA_SECRET_KEY: xxx`
в `.envs/production/secret.enc.yaml` → после пуша и деплоя переменная
автоматически появляется в контейнере backend.

Механика: деплой-скрипт → `vars.yml` → `env.j2` → `docker/env`.

- **CI (`docker/deploy_ci.sh`)**: собирает `ALL_DEPLOY_KEYS` из merged yq
  (`.envs/<env>/public.yaml` + расшифрованный `secret.enc.yaml`, **ВЕРХНИМ**
  регистром); в `deploy-env.sh` пишет все значения плюс `EXTRA_ENV_KEYS`
  (= все ключи минус `BASE_DEPLOY_KEYS` — базовые ключи деплоя: `SSH_*`,
  `DEPLOY_*`, `DOMAIN`, `PROJECT_*`, `BRAND_*`, `ADMIN_*`, `PROXY_DIR`,
  `ARCHIVE_PATH` и т.п., рендерятся отдельными полями `vars.yml`).
  В GitLab CI задаётся **только** age-ключ (`SOPS_AGE_KEY_TEST`/`SOPS_AGE_KEY_PRODUCTION`).
- **Ручной деплой (`deploy.sh`)**: список доп. переменных — `S3_ENV_VARS`
  (14 `S3_*`-переменных) + `PUBLIC_BASE_URL` + `MOCK_TELEGRAM_POST_URL` +
  расширяемый `EXTRA_DEPLOY_ENV_VARS` из корневого `.env`. Источники:
  `.env` → `apps/backend/.env.local` (gitignored).
- На сервере в `vars.yml` рендерится `extra_env: { KEY: "value" }`, а `env.j2`
  generic-циклом `{% for key, value in extra_env.items() %}` превращает это
  в `KEY=value`. `group_vars/all.yml` содержит одно поле `extra_env: {}` —
  отдельных s3_*/public_base_url/mock_telegram_post_url полей больше нет.
- `deploy-env.sh` на сервере — права **chmod 600** (содержит пароли/ключи).

S3-персистентность: значения кешируются в `<project_dir>/.app.s3` (umask 077,
shell-экранирование) — деплой без заданных `S3_*` не затирает настроенный S3.
`S3_*` идут через этот же generic-механизм. Файлы `.env.local` и `.app.s3`
исключены из tar-архивов деплоя.

Полная инструкция — в [`ansible/README.md`](../ansible/README.md) и
[`deploy.sh`](../deploy.sh). Логи — `logs/deploy.log`; в конце деплоя печатается
**маркер окончания**:

- `### DEPLOY-FINISHED: deploy.sh завершился успешно (exit 0) ###`
- `### DEPLOY-FAILED: deploy.sh завершился с ошибкой (exit N) ###`

См. «Отслеживание окончания деплоя по маркеру» в [`areas/ci-deployment.md`](areas/ci-deployment.md).

### Портируемость по форкам

- `PROJECT_NAME` — **обязателен** в `.env` (нет дефолта, нет хардкода).
- `project_dir`/`archive_path`/`db_username`/`db_name` выводятся из `project_name`.
- `group_vars/all.yml` — плейсхолдеры/выводимые; реальные значения — в `vars.yml`
  (плюс единое `extra_env: {}`).
- Проверка: `grep -rn "gmoreva-setup\|vibesetup_db\|/opt/vibesetup" deploy.sh ansible/ docker/ .env.example`
  — только плейсхолдеры/комментарии.

### Краткие шаги

1. Заполнить корневой `.env` (SSH_*, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD,
   PROJECT_NAME, BRAND_*).
2. `./deploy.sh` — собирает архив, sftp, генерация секретов, ansible-playbook.
3. Healthcheck: `https://<DOMAIN>/api/users/count` → 200.
4. Проверка версии: `curl https://<DOMAIN>/api/version` — `{ "version": "…", "commit": "…", "build": 1 }`.
   В CI-деплое `commit` проставляется автоматически (APP_COMMIT_SHA = SHA коммита);
   в ручном — через `EXTRA_DEPLOY_ENV_VARS="APP_COMMIT_SHA"` + `APP_COMMIT_SHA=…` в `.env`;
   `build` — хардкод в `apps/backend/src/version/version.controller.ts`.

### nginx-proxy (мульти-проект)

Общий `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion` поднимаются один раз
на сервере (тег `proxy`). Каждый проект-контейнер подключается к external-сети
`reverse-proxy` и объявляет `VIRTUAL_HOST`/`LETSENCRYPT_HOST`/`LETSENCRYPT_EMAIL`.

## Деплой через GitLab CI (автоматический)

Пайплайн `.gitlab-ci.yml` (этапы **build → deploy**) деплоит из Registry без
сборки на сервере: образы `frontend`/`backend` по тегу SHA, образ `ci-deploy`
(sops/yq/ssh внутри), секреты SOPS+age per-стенд. `deploy:test` запускается
на push в default-ветку и в `develop`. Подробно —
[`areas/ci-deployment.md`](areas/ci-deployment.md).

### Особенности ansible-ролей

- **`app`**: после `docker compose up -d` — ожидание готовности PostgreSQL
  (`pg_isready` с ретраями) и idempotent-синхронизация пароля роли через
  `ALTER USER` (`no_log`, экранирование кавычек) с рестартом backend при
  изменении. Лечит ошибку `28P01` при смене `db_password`.
- **`nginx_proxy`**: создаёт `{{ proxy_dir }}/vhost.d/default` с
  `client_max_body_size 500M` (nginx-proxy по умолчанию режет тела >1M —
  413). `compose-proxy.yml.j2` монтирует `vhost.d` с хоста (bind-mount);
  при изменении `vhost.d/default` выполняется reload nginx-proxy.

Логи CI-деплоя (`logs/deploy-ci.log`) и маркеры DEPLOY-* —
см. [`areas/ci-deployment.md`](areas/ci-deployment.md).

## Частые ошибки

1. **JWT-secret по дефолту** — замените `dev-secret-change-me` на production-ключ.
2. **CORS blocked** — `CORS_ORIGIN` backend должен включать домен (prod) /
   `http://localhost:3000` (dev). SSR-фетч идёт мимо CORS.
3. **Backend не стартует** — проверьте `docker compose logs backend`; частая
   причина — PostgreSQL ещё не готов. Backend сам ретраит подключение
   (5 попыток × 3с) и создаёт БД при отсутствии (`ensure-database.ts`).
4. **`/api` 404 на клиенте** — Nuxt не проксирует: проверьте `routeRules` в
   `nuxt.config.ts` и `NUXT_API_BASE`.
5. **401 на /admin под SSR** — cookie не проксируется: проверьте `useApi`
   (`useRequestHeaders(['cookie'])`).
6. **Cookie не ставится** — `COOKIE_SECURE=true` требует HTTPS; в dev оставьте
   пустым/false.
CI-специфичные ошибки (пропущенный деплой, `docker pull` 401) —
см. [`areas/ci-deployment.md`](areas/ci-deployment.md) «Требования и ограничения».

## Чек-лист деплоя

- [ ] nginx-proxy + acme-companion запущены, сеть `reverse-proxy` доступна
- [ ] `.env` (deploy.sh) заполнен: `PROJECT_NAME`, `DOMAIN`, `LETSENCRYPT_EMAIL`,
      `ADMIN_PASSWORD`, SSH-креды
- [ ] `JWT_SECRET` — production-ключ (генерируется в `.app.secrets`)
- [ ] `COOKIE_SECURE=true` (прод, HTTPS); `CORS_ORIGIN` = домен (ansible)
- [ ] `DB_SYNCHRONIZE=false` (prod — миграции при старте)
- [ ] Миграции накатываются (`docker compose logs backend` — нет ошибок TypeORM)
- [ ] DNS-запись домена указывает на IP сервера
- [ ] `docker compose -p <project> -f docker-compose.prod.yml up -d --build` прошёл
- [ ] PostgreSQL healthcheck прошёл
- [ ] HTTPS-сертификат получен (acme-companion)
- [ ] `curl -I https://<DOMAIN>/` → 200 (frontend SSR)
- [ ] `curl https://<DOMAIN>/api/users/count` → 200 (прокси → backend)
- [ ] `curl https://<DOMAIN>/api/auth/me` → 401 (без cookie)