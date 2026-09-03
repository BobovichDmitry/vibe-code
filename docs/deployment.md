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

При старте backend сам создаёт `DB_DATABASE`, если её нет (том postgres мог быть
проинициализирован с другим именем — переименование проекта, старый деплой;
раньше был бы `FATAL: database "X" does not exist`). Нужно право `CREATEDB` у
`DB_USERNAME` (в шаблоне `POSTGRES_USER` — superuser). См. `docs/areas/database-structure.md`.

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

Логи деплоя: `./deploy.sh` дублирует весь свой вывод в **`logs/deploy.log`**
(в терминале вывод остаётся прежним). Каждый запуск дописывается в файл с
заголовком-разделителем по времени запуска.

В конце каждого деплоя (в stdout и в лог) печатается **маркер окончания**:

- `### DEPLOY-FINISHED: deploy.sh завершился успешно (exit 0) ###`
- `### DEPLOY-FAILED: deploy.sh завершился с ошибкой (exit N) ###`

См. «Отслеживание окончания деплоя по маркеру» ниже.

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
  (`$CI_REGISTRY_IMAGE/{frontend,backend}`) с двумя тегами: `$CI_COMMIT_SHORT_SHA`
  (иммутабельный, именно его пуллят джобы деплоя) + `$CI_COMMIT_REF_SLUG`
  (движущийся тег текущей ветки). Тег `latest` НЕ создаётся.
- **`deploy:test` / `deploy:production`** — деплой из Registry **без сборки на
  сервере**: каждая джоба экспортирует per-стенд age-ключ (`SOPS_AGE_KEY_TEST` /
  `SOPS_AGE_KEY_PRODUCTION` → `SOPS_AGE_KEY`), `DEPLOY_ENV` и запускает
  [`docker/deploy_ci.sh`](../docker/deploy_ci.sh). `resource_group` на каждой
  джобе защищает от параллельных деплоев одного окружения.

### Шифрование энвов (SOPS + age)

Секреты окружений хранятся **зашифрованными прямо в git** — механика SOPS + age
(как в ai-provider). В GitLab Variables лежит ТОЛЬКО ключ расшифровки.

Структура `.envs/`:

```
.envs/
├── test/
│   ├── public.yaml        # несекретное: SSH_HOST, DOMAIN, PROJECT_NAME, BRAND_*, ...
│   ├── secret.yaml        # секретное (gitignored!): ADMIN_PASSWORD, DEPLOY_SSH_KEY
│   └── secret.enc.yaml    # зашифрованный secret.yaml (в git)
└── production/
    ├── public.yaml
    ├── secret.yaml        # (gitignored)
    └── secret.enc.yaml
```

- **public.yaml** — несекретные значения (в git открыто);
- **secret.yaml** — секретные значения, **в `.gitignore`**; шаблон — `secret.yaml.example`;
- **secret.enc.yaml** — результат шифрования `secret.yaml` через sops+age, **в git**;
- **`.agekey`** — приватный age-ключ (gitignored), **`.agekey.public`** — recipient (в git).

Переменные окружения в yaml — **ВЕРХНИМ регистром** (`SSH_HOST`, `ADMIN_PASSWORD`,
`DEPLOY_SSH_KEY`), т.к. экспортируются в env. `DEPLOY_SSH_KEY` — `base64` приватного
SSH-ключа деплоя (`base64 -w0 path/to/id_rsa`), без passphrase.

Цикл работы с секретами:

```bash
# 0) Первичная генерация пары ключей (один раз; приватный НЕ коммитить):
age-keygen -o .agekey          # создаёт .agekey (gitignored); public — вторая строка файла
cat .agekey | grep -o 'age1.*' > .agekey.public

# 1) Заполни секреты:
cp .envs/test/secret.yaml.example .envs/test/secret.yaml   # и заполни

# 2) Зашифруй и закоммить результат:
bash scripts/encrypt.sh test     # обновляет .envs/test/secret.enc.yaml
git add .envs/test/secret.enc.yaml .agekey.public

# 3) Обратно (поредактировать): bash scripts/decrypt.sh test
```

Требуются `sops` и `age-keygen`/`age` ([sops](https://github.com/getsops/sops),
[age](https://github.com/FiloSottile/age)).

### GitLab Variables (Settings → CI/CD → Variables, флаги protected + masked)

| Variable | Окружение |
|----------|-----------|
| `SOPS_AGE_KEY_TEST` | тест-сервер — приватный age-ключ стенда |
| `SOPS_AGE_KEY_PRODUCTION` | прод-сервер — приватный age-ключ стенда |

Каждая переменная — **содержимое приватного age-ключа** (вторая строка файла
`.agekey`, начинающаяся с `AGE-SECRET-KEY-`). Ключи per-стенд: расшифровать
тестовые секреты продовым ключом нельзя.

Старые `DEPLOY_BUNDLE_*`, `DEPLOY_HOST` / `DEPLOY_PATH` / `SSH_PRIVATE_KEY` /
`DEPLOY_COMPOSE_PROJECT` больше **не используются**.

### Локальный тест-запуск

```bash
# Ключ — из ./.agekey (gitignored) или env SOPS_AGE_KEY; registry-логин скипается,
# если CI_REGISTRY/CI_JOB_TOKEN не заданы (docker login в registry на сервере сделан руками).
DEPLOY_ENV=test \
FRONTEND_IMAGE="registry.example.com/proj/frontend:abc123" \
BACKEND_IMAGE="registry.example.com/proj/backend:abc123" \
  bash docker/deploy_ci.sh
# Либо всё готовыми значениями: ./deployci-test.sh (DEPLOY_ENV=test по умолчанию)
```

### Поток docker/deploy_ci.sh

1. Расшифровывает `.envs/$DEPLOY_ENV/secret.enc.yaml` через `SOPS_AGE_KEY`
   (sops + age), мержит с `public.yaml` (yq; secret перекрывает public) и
   экспортирует всё как переменные окружения; `DEPLOY_SSH_KEY` (base64)
   → временный `id_rsa` (chmod 600).
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

Логи деплоя: `deploy_ci.sh` дублирует весь свой вывод в **`logs/deploy-ci.log`**
(и в stdout, т.е. в лог CI-джобы). Каждый запуск дописывается в файл с
заголовком-разделителем по времени запуска.

## Отслеживание окончания деплоя по маркеру

Оба скрипта деплоя в самом конце печатают маркер окончания (trap на EXIT —
печатается всегда, и при успехе, и при провале):

| Маркер | Значение |
|---|---|
| `### DEPLOY-FINISHED: ... (exit 0) ###` | деплой завершился успешно |
| `### DEPLOY-FAILED: ... (exit N) ###` | деплой завершился с ошибкой |

Маркер попадает и в stdout, и в лог-файл (`logs/deploy.log` / `logs/deploy-ci.log`).
Это позволяет не следить за логом бесконечно, а дождаться появления маркера.

Примеры ожидания маркера в локальном логе:

```bash
# 1) Ждать маркер в реальном времени (Ctrl+C после появления — tail сам не выйдет,
#    маркер печатается ПЕРЕД завершением скрипта):
tail -f logs/deploy.log

# 2) Однократная проверка «деплой ещё идёт или уже закончился?» по последнему запуску:
grep -E 'DEPLOY-(FINISHED|FAILED)' logs/deploy.log | tail -1

# 3) Запустить деплой и автоматически вернуться, когда появится маркер:
./deploy.sh 2>&1 | sed -n '/### DEPLOY-/q;p'
```

Для CI-деплоя аналогично: маркер `### DEPLOY-FINISHED ###` в конце лога джобы
GitLab означает, что деплой дошёл до конца; `### DEPLOY-FAILED ###` — джоба
упадёт (exit code ≠ 0). Ожидать окончания можно также по статусу pipeline
(`success` / `failed` у джобы `deploy:test` / `deploy:production`).

### Требования и ограничения CI-деплоя

- **Age-ключ не задан → деплой пропускается**: джоба завершается успешно с
  warning'ом в консоли («деплой пропущен»), пайплайн остаётся зелёным. Чтобы деплой
  заработал — заведите `SOPS_AGE_KEY_*` в Settings → CI/CD → Variables
  (protected+masked).
- Ветка `master` — **protected**: иначе protected-переменные недоступны и джоба
  пропустит деплой (а не упадёт) — ключ просто не будет виден на непротектед ветке.
- **Host key сервера**: по умолчанию `StrictHostKeyChecking=accept-new` — если сервер
  пересоздан и в known_hosts раннера остался старый ключ, деплой упадёт с
  `REMOTE HOST IDENTIFICATION HAS CHANGED`. Отключить проверку — переменная
  `DEPLOY_SKIP_HOST_KEY_CHECK=1` (Settings → CI/CD → Variables; НЕБЕЗОПАСНО — MITM-риск);
  безопасная альтернатива — `ssh-keygen -R <host>` на раннере.
- `CI_JOB_TOKEN` открывает только Registry **своего** проекта; для образов из
  чужого проекта нужен deploy token.
- Чек-лист: оба образа в Registry (тег SHA) → age-ключи заведены (protected+masked,
  ветка protected) → секреты зашифрованы и закоммичены (`.envs/*/secret.enc.yaml`) →
  DNS домена указывает на IP сервера → джобы зелёные →
  `curl https://<DOMAIN>/api/users/count` → 200.

## Частые ошибки

1. **JWT-secret по дефолту** — замените `dev-secret-change-me` на production-ключ.
2. **CORS blocked** — `CORS_ORIGIN` backend должен включать домен (prod) /
   `http://localhost:3000` (dev). SSR-фетч идёт мимо CORS.
3. **Backend не стартует** — проверьте `docker compose logs backend`; частая
   причина — PostgreSQL ещё не готов. Backend сам ретраит подключение
   (5 попыток × 3с) и создаёт БД при отсутствии (`ensure-database.ts`);
   если всё равно падает — проверьте `DB_USERNAME`/`DB_PASSWORD` и право `CREATEDB`.
4. **`/api` 404 на клиенте** — Nuxt не проксирует: проверьте `routeRules` в
   `nuxt.config.ts` и `NUXT_API_BASE`.
5. **401 на /admin под SSR** — cookie не проксируется: проверьте `useApi`
   (`useRequestHeaders(['cookie'])`).
6. **Cookie не ставится** — `COOKIE_SECURE=true` требует HTTPS; в dev оставьте
   пустым/false.
7. **Deploy-джоба зелёная, но деплой пропущен (warning в логе)** — age-ключ
   (`SOPS_AGE_KEY_TEST` / `SOPS_AGE_KEY_PRODUCTION`) не заведён в
   Settings → CI/CD → Variables, или ветка не protected (protected-переменные
   недоступны на обычных ветках). Заведите ключ — и деплой включится
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