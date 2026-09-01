CI-деплой в два этапа (build → deploy) с бандл-переменными GitLab: один base64-бандл на окружение (SSH-ключ + .env), новый `docker/deploy_ci.sh` — pull собранных образов из Registry на сервере (без сборки), полная подготовка нового сервера с нуля (ansible, docker, nginx-proxy), автодеплой обоих окружений (тест + прод) на push в master.

---

## Контекст (анализ кода)

**Что есть сейчас:**

- `.gitlab-ci.yml` (коммит `e6e154c`): два этапа `build` / `deploy`.
  - `build:docker` — docker build + push обоих образов в Registry: `$CI_REGISTRY_IMAGE/{frontend,backend}` с тегами `$CI_COMMIT_SHORT_SHA` + `$CI_COMMIT_REF_SLUG`, `latest` на default-ветке. Правила: на любую ветку/тег.
  - `.base_deploy` + `deploy:production` — SSH (image `obvu/ssh_deployer`), на сервере `docker compose -f docker-compose.prod.yml pull frontend backend` + `up -d` с `FRONTEND_IMAGE`/`BACKEND_IMAGE` (тег по SHA). Переменные: `SSH_PRIVATE_KEY`, `DEPLOY_HOST`, `DEPLOY_PATH`, `DEPLOY_COMPOSE_PROJECT` (GitLab CI/CD Variables). Автодеплой: `$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`.
- `deploy.sh` — ручной деплой без CI: читает корневой `.env` (SSH_HOST, SSH_USER, SSH_KEY, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD, PROJECT_NAME, PROJECT_DIR, ARCHIVE_PATH, PROXY_DIR, BRAND_*, ADMIN_LOGIN), ставит ansible на сервере с нуля, tar.gz исходников + sftp, генерирует `.app.secrets` и `ansible/vars.yml`, запускает `ansible-playbook playbook.yml -e @vars.yml`. **По требованию пользователя — НЕ трогаем** (остаётся для ручных деплоев).
- `ansible/playbook.yml` — роли: `docker` (tag deps), `nginx_proxy` (tag proxy), `app` (tag deploy) + healthcheck; `ansible_connection=local` (запуск на сервере).
- `ansible/roles/app/tasks/main.yml` — создаёт project_dir, распаковывает архив, рендерит `docker/env` из `templates/env.j2` и `docker/.env`, **делает `docker compose build` НА СЕРВЕРЕ**, `up -d`. Для CI-схемы здесь нужен режим pull вместо build.
- `docker/docker-compose.prod.yml` — уже поддерживает CI-режим: `image: ${FRONTEND_IMAGE:-app-frontend:local}` / `${BACKEND_IMAGE:-app-backend:local}`; при заданных переменных делает pull + up, секции `build:` игнорируются.
- GitLab MCP-инструмент `gitlab_validate_ci_lint` — можно провалидировать новый `.gitlab-ci.yml`.

**Чего не хватает (суть задачи):**

- Схема деплой-переменных: сейчас несколько разрозненных переменных на один таргет; нужен **один base64-бандл на окружение** (SSH-ключ + `.env`), из которого джоба собирает всё для деплоя.
- Скрипт CI-деплоя с **полной подготовкой пустого сервера** и **pull-ом образов** (сборка — только на этапе build в CI).
- Мульти-деплой: два окружения (тест + прод) из одного пайплайна.

## Acceptance criteria

- Push в `master` → пайплайн: `build` (оба образа в Registry, теги SHA) → `deploy:test` и `deploy:production` — **оба автоматом** (по решению пользователя; перевести прод на manual потом — оставляем точку расширения).
- **Сервер не собирает образы**: деплой = `docker compose pull` + `up -d` из Registry; теги по SHA (`FRONTEND_IMAGE`/`BACKEND_IMAGE`).
- Деплой-переменные — **одна CI-variable на окружение**: `DEPLOY_BUNDLE_TEST`, `DEPLOY_BUNDLE_PRODUCTION` — base64-бандл из приватного SSH-ключа + содержимого `.env` (SSH_HOST, SSH_USER, SSH_KEY, SSH_PORT, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_LOGIN, ADMIN_PASSWORD, PROJECT_NAME, опц. PROJECT_DIR/PROXY_DIR/BRAND_*). Переменные — protected + masked.
- Новый `docker/deploy_ci.sh` (deploy.sh не изменён):
  - декодирует бандл на раннере → ключ в `~/.ssh/id_rsa`, `.env` рядом;
  - на **пустом** сервере ставит всё с нуля: ansible → docker (роль deps) → nginx-proxy + acme (роль proxy) → приложение;
  - для пулла образов получает **временный токен** (`CI_JOB_TOKEN`: `docker login $CI_REGISTRY -u gitlab-ci-token --password-stdin` — живёт только в пределах джобы);
  - non-interactive (никаких `read` из /dev/tty, DNS-предупреждение — просто warning в лог).
- `docker-compose.prod.yml` в CI-режиме работает как раньше (интерполяция из `docker/.env`, `-p` из PROJECT_NAME).
- Ручной деплой `deploy.sh` работает без изменений (регресс — не сломать).
- Справочно в задаче/доках: команда формирования бандла (helper-скрипт или однострочник) и перечень переменных `.env`.

## Подсказки по реализации

- **Файлы**: новый `docker/deploy_ci.sh`; правки `.gitlab-ci.yml` (новый `.base_deploy_ci` + два джобы `deploy:test`/`deploy:production`); режим pull в `ansible/roles/app/tasks/main.yml` (deploy.sh не трогаем; ansible-роль править можно — иначе сборка на сервере не уберётся); опционально `scripts/make_deploy_bundle.sh` + обновление docs (deployment.md).
- **Формат бандла**: `tar czf - id_rsa .env | base64 -w0` → одна строка (маскируется в GitLab). На старте джобы: `base64 -d | tar xzf -` в `~/.deploy/` (0700), ключ chmod 600, удалить в `after_script`. Helper: `scripts/make_deploy_bundle.sh <id_rsa> <.env>` → печатает строку для вставки в CI variable.
- **Режим pull в ansible-роли app**: если заданы `frontend_image`/`backend_image` (extra vars из CI) — шаг `docker compose build` заменить на `docker compose pull frontend backend` (перед этим `docker login $CI_REGISTRY` с токеном, после — `docker logout`), а `FRONTEND_IMAGE`/`BACKEND_IMAGE` прокинуть в `docker/.env` (env.j2 или copy content). Без этих vars — старое поведение (build) для deploy.sh.
- **vars.yml на сервере**: `deploy_ci.sh` собирает его сам из распакованного `.env` бандла (как deploy.sh) + секреты `.app.secrets` (генерация на сервере при первом деплое, переиспользование при повторных).
- **Репозиторий на раннере**: `GIT_STRATEGY: fetch` (нужны `ansible/` и `docker/` для архива и ролей) — в отличие от текущего `.base_deploy` (там `none`).
- **Временный токен**: `CI_JOB_TOKEN` доступен на раннере; на сервер передавать через SSH-команду (`--password-stdin`). Работает только для Registry своего проекта — этого достаточно.
- **SSH-секьюрити на раннере**: как в текущем `.base_deploy` (mkdir ~/.ssh, chmod 600, rm в after_script, `StrictHostKeyChecking=accept-new`).
- **Два окружения**: разные бандлы → можно разные серверы ИЛИ один сервер (разный PROJECT_NAME в `.env` → разные `-p` и PROJECT_DIR). Логика в скрипте одинаковая.
- **Осторожно**: protected variable доступна только на protected-ветках — master должен быть protected (иначе деплой упадёт с пустым бандлом; добавить в скрипте внятную ошибку `DEPLOY_BUNDLE_* не задан`).

## Проверка

- `bash -n docker/deploy_ci.sh` (синтаксис), `shellcheck docker/deploy_ci.sh` (если установлен).
- Валидация `.gitlab-ci.yml`: `gitlab_validate_ci_lint` (GitLab CI Lint API) — конфиг валиден, обе deploy-джобы видны для ветки master.
- e2e/dev-серверы не запускать (по правилам проекта). Проверка реального деплоя — на живом пайплайне пользователем.

---

## Уточнения из диалога (кратко)

1. **Раунд 1**: сервер не должен собирать образ (только pull+run); мульти-деплой (тест + прод); архитектура «общий раннер → SSH на сервер».
2. **Раунд 2**: деплой должен идти через deploy.sh-подобный скрипт с .env из CI-переменной (base64-бандл: SSH-ключ + .env), fork от `.base_deploy`, всё автоматически.
3. **Раунд 3**: deploy.sh НЕ трогать (ручные деплои) → новый `docker/deploy_ci.sh`; временный токен для пулла образов; полная подготовка пустого сервера внутри CI-скрипта. Прод — тоже автомат (пока, поменяем потом).
---

## Реализация (2026-09-05)

### Что сделано

- **`docker/deploy_ci.sh`** (новый) — CI-деплой из base64-бандла:
  - декодирует бандл (`DEPLOY_BUNDLE` из CI или `./.ci-bundle` из корня для локального теста) → SSH-ключ + `.env`;
  - ставит ansible на сервере с нуля, собирает tar.gz исходников + deploy-env.sh, заливает через sftp;
  - генерирует `.app.secrets` (один раз) и `ansible/vars.yml` на сервере;
  - **registry-логин только в CI** (`CI_REGISTRY` + `CI_JOB_TOKEN`, токен через stdin) — при ручном тест-запуске скипается (считается, что авторизация в registry на сервере сделана руками);
  - запускает `ansible-playbook` с `-e frontend_image/backend_image` → сервер **пуллит** образы, не собирает;
  - `docker logout` после деплоя; healthcheck по `https://$DOMAIN/api/users/count`.
- **`.gitlab-ci.yml`** — деплой-секция переработана: старый `.base_deploy`/`deploy:production` (SSH+pull по DEPLOY_HOST) удалён; новый `.base_deploy_ci` (image `ubuntu:24.04`, `GIT_STRATEGY: fetch`) + две джобы `deploy:test` и `deploy:production` — **обе автоматом на default-ветку (master)**, каждая со своим бандлом (`DEPLOY_BUNDLE_TEST` / `DEPLOY_BUNDLE_PRODUCTION`), `environment: name:` + `resource_group`. Build-этап не менялся.
- **`ansible/roles/app/tasks/main.yml`** — CI-режим: при заданных `frontend_image`/`backend_image` — `lineinfile` прокидывает `FRONTEND_IMAGE`/`BACKEND_IMAGE` в `docker/.env` + `docker compose pull frontend backend`; `build` — только в ручном режиме (deploy.sh). deploy.sh не тронут.
- **`scripts/make_deploy_bundle.sh`** (новый) — формирует бандл: `tar.gz[id_rsa, .env] | base64 -w0`, с предупреждениями (passphrase в ключе, отсутствующие обязательные переменные .env). Вывод → GitLab Variable ИЛИ `> .ci-bundle` для локального теста.
- **`.gitignore`** — `/.ci-bundle` (бандл содержит приватный ключ — коммитить нельзя).

### Ключевые решения

- Один CI-variable на окружение (base64-бандл) вместо набора DEPLOY_HOST/DEPLOY_PATH/... — проще заводить окружения, значение проходит под GitLab mask (одна строка) и хранится protected.
- Временный токен — `CI_JOB_TOKEN` (живёт в рамках джобы), логин через stdin; после деплоя logout. Для ручного теста — просто не задавать CI_REGISTRY/CI_JOB_TOKEN.
- Подготовка пустого сервера переиспользует существующие ansible-роли (deps/proxy/app) — добавлен только режим Registry в роли app.
- resource_group на каждую deploy-джобу — защита от параллельных деплоев одного окружения.

### Как проверено

- `bash -n` — оба новых скрипта; python-yaml — `.gitlab-ci.yml` и ansible-роль (локальный парсинг).
- Round-trip бандла: `make_deploy_bundle.sh` → base64 → декод → файлы id_rsa/.env на месте; предупреждения о недостающих переменных .env работают.
- GitLab CI Lint через API — 403 (права токена MCP недостаточны), провалидировать после коммита через CI/CD → Editor → Validate.
- Реальный прогон — на живом сервере пользователем (см. тест-запуск в шапке deploy_ci.sh).

### Остаточные риски / TODO

- Прод-джоба пока автоматом на master (по решению пользователя; перевести на `when: manual` позже — поменять одну строку rules/when).
- `CI_JOB_TOKEN` по умолчанию даёт доступ только к Registry своего проекта — если образы будут тянуться из другого проекта, нужен deploy token.
- Пайплайн выполняет код из репо: первый реальный CI-прогон возможен только после коммита/пуша этих изменений.
- `ubuntu:24.04` ставит openssh-client/curl каждый прогон (~2-5 сек) — при желании можно уйти на готовый образ с ssh.

### Доработка (2026-09-05, по запросу пользователя)

- Если бандл-переменная окружения (`DEPLOY_BUNDLE_TEST` / `DEPLOY_BUNDLE_PRODUCTION`) **не задана совсем** — deploy-джоба **пропускает деплой** с warning'ом в консоли («деплой пропущен») и завершается успехом (пайплайн зелёный), вместо падения. Проверка — early-exit в начале `script:` каждой джобы; установка пакетов тоже не выполняется при скипе.
- `docs/deployment.md` — синхронизированы раздел «Требования и ограничения» и «Частые ошибки» (п. 7).

### Фикс сборки backend (2026-09-01, из живого пайплайна git.obvu.ru)

- `build:docker` падал на `Dockerfile.backend`, production-стадия: `npm install --omit=dev --workspace=apps/backend` → `npm error Cannot read properties of null (reading 'edgesOut')` (баг arborist npm 10.9.x: без `package-lock.json` + workspaces + omit=dev).
- Причина: в production-стадии копировался только `package.json` без лока; баг всплыл после обновления `node:22-alpine` (docker build `--pull`).
- Фикс: `COPY package.json package-lock.json ./` + `npm ci --omit=dev --workspace=apps/backend` (детерминированно, минуя резолвинг arborist).
- Проверено локально: `docker build -f docker/Dockerfile.backend .` — OK; smoke-тест образа — контейнер поднялся, `GET /api/users/count` → `{"total":1,"adminCount":1}`.

### Доработка 2 (2026-09-05): skip проверки host key + мягкая установка зависимостей

- Новая опциональная CI-переменная `DEPLOY_SKIP_HOST_KEY_CHECK=1` — отключает проверку host key сервера (`StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null`) — для пересозданных серверов со старым ключом в known_hosts раннера (ошибка `REMOTE HOST IDENTIFICATION HAS CHANGED` в первом CI-прогоне). По умолчанию `accept-new`.
- Установка ssh/curl перенесена в `deploy_ci.sh` и стала условной: на shell-раннере (не root) пакеты уже есть → apt не запускается (убраны ошибки Permission denied из лога); в docker-образе ubuntu — ставится.
- Документировано в `.gitlab-ci.yml` (шапка) и `docs/deployment.md`.

### Доработка 3 (2026-09-05): автосоздание БД при старте backend

- Проблема с нового деплоя: `postgres FATAL: database "gmoreva-platform" does not exist` — POSTGRES_DB в контейнере postgres применяется только при ПЕРВОЙ инициализации тома; при переименовании проекта/старом томе backend не мог подключиться.
- Фикс: `apps/backend/src/database/ensure-database.ts` — при старте (DB_TYPE=postgres) backend подключается к системной базе `postgres` (5 попыток × 3с), проверяет pg_database и создаёт DB_DATABASE, если её нет; далее TypeORM migrationsRun накатывает таблицы. sqlite — no-op. Вызов в `main.ts` до Nest bootstrap.
- Проверено: tsc --noEmit; интеграционный тест на живом postgres-контейнере (создание недостающей БД + идемпотентный повтор). Доки обновлены (database-structure, backend-api-structure, deployment).
- Попутно обнаружено на сервере: осиротевший compose-проект `docker` (/opt/docker, дубль gmoreva-platform с тем же volume/env) — кандидат на `docker compose -p docker down` + удаление.

### Доработка 4 (2026-09-05): FATAL "database does not exist" в логах postgres — шум healthcheck'а

- Диагноз (по живому серверу): БД создалась при первой инициализации тома; 1524 FATAL'а "database \"<user>\" does not exist" с интервалом ровно 5с — это healthcheck `pg_isready -U ${DB_USERNAME}` без `-d`: pg_isready дефолтит на БД = имя юзера, которой нет (есть только `<project>_db`). pg_isready всё равно возвращает 0, healthcheck = healthy, приложение работало.
- Фикс: `docker/docker-compose.prod.yml` — healthcheck теперь `pg_isready -U ${DB_USERNAME} -d ${DB_DATABASE}` (проверяет реальную БД, шум исчезнет после следующего `up`/пересоздания контейнера postgres).
- ensure-database.ts (Доработка 3) остаётся: закрывает реальные случаи рассинхрона тома и env.
