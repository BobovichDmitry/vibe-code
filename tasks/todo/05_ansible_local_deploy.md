Подготовить ansible-скрипты, которые запускаются **НА целевом сервере** (не на ПК разработчика). Текущий ПК только через sftp передаёт архив с исходниками на сервер; дальше ansible настраивает сервер, ставит зависимости (Docker/compose и т.д.), собирает и поднимает проект. Среди переменных — IP адрес сервера и домен.

> **Решения по вопросам:** Q3=B — HTTPS через **nginx-proxy** (`nginxproxy/nginx-proxy` + `acme-companion`), общий на все будущие проекты сервера; Q4=A — отдельный `docker-compose.prod.yml` без проброса `5432` наружу, app подключается к external-сети `reverse-proxy`; Q7=A — архив `tar.gz` исходников, сборка идёт на сервере внутри Docker (multi-stage Dockerfile).

---

## Контекст (анализ кода)

Текущая поставка:
- `docker/Dockerfile` — multi-stage (frontend build → backend build → prod), `CMD ["node","apps/backend/dist/main.js"]`, `EXPOSE 3000`, SQLite-папка `/app/apps/backend/data`.
- `docker/docker-compose.yml` — сервис `app` (build context `../`, `dockerfile: docker/Dockerfile`, `ports 3000:3000`, `env_file ./env`, `restart: unless-stopped`) + `postgres` (`postgres:16-alpine`, `pg_data` volume). `docker/env` — прод-env шаблон (`DB_TYPE=postgres`, `DB_HOST=postgres`, `CORS_ORIGIN=https://app.example.com`, `JWT_SECRET`, `ADMIN_LOGIN/PASSWORD`).
- `docker/docker-compose.nginx-proxy.yml` — вариант с nginx-proxy + Let's Encrypt (мультитенантный паттерн референса). **Решено Q3 — берётся именно этот паттерн** (вариант B), чтобы держать несколько проектов на одном сервере в будущем: общий `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion` поднимаются один раз (общая reverse-proxy сеть), а каждый проект-контейнер подключается к этой сети и объявляет `VIRTUAL_HOST`/`LETSENCRYPT_HOST`.
- Корневой `package.json` — workspace, `npm run build`, `start:prod`.

Постановка от пользователя:
1. На ПК: собирается архив исходников (весь проект, без `node_modules`/`dist`/`logs`/`data`).
2. Через sftp архив копируется на сервер (например в `/opt/vibesetup/`).
3. На сервере запускается ansible (локально, `connection: local` или `hosts: localhost`), который:
   - ставит системные зависимости (Docker, docker compose plugin, git, и т.п.);
   - распаковывает архив;
   - формирует `docker/env` (или `.env`) из переменных ansible (домен, IP, пароль БД, JWT_SECRET, ADMIN_*);
   - собирает и поднимает `docker compose` (app + postgres);
   - при необходимости — ставит nginx + certbot, настраивает HTTPS-проксирование на `:3000` для домена;
   - проверяет здоровье (`curl http://localhost:3000/api/users/count`).

Ansible запускается именно на сервере → `inventory` с `ansible_connection=local`, `ansible_host=127.0.0.1`. Переменные `server_ip` и `domain` задаются в `group_vars`/`inventory`/`--extra-vars`.

## Acceptance criteria

- [ ] Создана папка `ansible/` в корне проекта со структурой:
  ```
  ansible/
    ansible.cfg
    inventory.ini            # localhost, ansible_connection=local
    group_vars/all.yml       # переменные: server_ip, domain, db_password, jwt_secret, admin_login, admin_password, проектный путь и т.п. (значения — плейсхолдеры + комментарии)
    vars.example.yml         # пример заполнения переменных (для копирования)
    playbook.yml             # основной плейбук (tags: deps, proxy, deploy, healthcheck)
    roles/                   # (опционально) разбивка по ролям
      docker/                # установка Docker + compose
      nginx_proxy/           # поднятие общего nginx-proxy + acme-companion (один раз на сервере)
      app/                   # распаковка архива, env, build/up
    templates/
      env.j2                 # docker/env (или .env) для приложения
      compose-proxy.yml.j2   # docker-compose для nginx-proxy + acme (общий)
    README.md                # инструкция: как собрать архив, как передать по sftp, как запустить ansible на сервере
  ```
- [ ] `ansible.cfg`: `inventory = inventory.ini`, `host_key_checking = False`, `interpreter_python = /usr/bin/python3`.
- [ ] `inventory.ini`: одна группа `[vibesetup]` с `localhost ansible_connection=local`. Переменные `server_ip`/`domain` вынесены в `group_vars/all.yml` (плейсхолдеры).
- [ ] `group_vars/all.yml`: переменные `server_ip`, `domain`, `project_dir` (дефолт `/opt/vibesetup`), `archive_path` (путь к загруженному архиву на сервере), `proxy_dir` (дефолт `/opt/nginx-proxy`, где живёт общий compose proxy), `db_password`, `db_username`, `db_name`, `jwt_secret`, `admin_login`, `admin_password`, `cors_origin` (=`https://{{ domain }}`), `letsencrypt_email`. Все секреты — плейсхолдеры/`!vault` с комментариями «заполнить перед запуском».
- [ ] Плейбук `playbook.yml` с тегами:
  - **deps**: установка Docker Engine + `docker-compose-plugin` (через официальный apt-репозиторий Docker; поддержка Debian/Ubuntu), `git`, `curl`, `ca-certificates`. Идемпотентно. Проверка `docker --version` / `docker compose version`.
  - **proxy**: поднятие **общего nginx-proxy** один раз на сервере (идемпотентно — если уже есть, пропуск). Создаётся `proxy_dir`, туда рендерится `templates/compose-proxy.yml.j2` (контейнеры `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion`, общая docker-сеть `reverse-proxy`, тома для letsencrypt/dhparam/html). `docker compose -f compose-proxy.yml up -d`. Сеть `reverse-proxy` — external, используется и app-контейнером. Повторный запуск не пересоздаёт сертификаты.
  - **deploy**: создание `project_dir`, распаковка архива (`unarchive`, `remote_src: yes`, формат `tar.gz` исходников — сборка идёт **на сервере** внутри Docker по multi-stage Dockerfile), генерация `docker/env` из `templates/env.j2`, `docker compose -f docker-compose.prod.yml build`, `docker compose -f docker-compose.prod.yml up -d`. App-контейнер подключается к external-сети `reverse-proxy` и объявляет `VIRTUAL_HOST={{ domain }}`, `LETSENCRYPT_HOST={{ domain }}`, `LETSENCRYPT_EMAIL={{ letsencrypt_email }}`, `CORS_ORIGIN=https://{{ domain }}`, `DB_SYNCHRONIZE=false` (прод-режим миграций из задачи 03 — автозапуск при старте Nest).
  - **healthcheck**: `uri`/`command curl` на `http://localhost:3000/api/users/count` (или через nginx-proxy `https://{{ domain }}/api/users/count` после выпуска сертификата) → ожидается `200` + JSON с `count`. fail, если не 200.
- [ ] Шаблон `templates/env.j2` (или `docker/env.j2`) рендерит прод-env: `DB_TYPE=postgres`, `DB_HOST=postgres`, `DB_PORT=5432`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`, `DB_SYNCHRONIZE=false`, `JWT_SECRET`, `ADMIN_LOGIN`, `ADMIN_PASSWORD`, `BRAND_TITLE`, `BRAND_FAVICON_URL` (из задачи 04), `CORS_ORIGIN=https://{{ domain }}`, `PORT=3000`, `VIRTUAL_HOST={{ domain }}`, `LETSENCRYPT_HOST={{ domain }}`, `LETSENCRYPT_EMAIL={{ letsencrypt_email }}`.
- [ ] Шаблон `templates/compose-proxy.yml.j2` — общий compose для nginx-proxy: сервис `nginx-proxy` (`nginxproxy/nginx-proxy`, порты `80:80`/`443:443`, тома `/etc/nginx/conf.d`, `/etc/nginx/vhost.d`, `/usr/share/nginx/html`, `/etc/nginx/certs`, env `DEFAULT_HOST={{ domain }}` опц.) + `acme-companion` (`nginxproxy/acme- companion`, `volumes_from: nginx-proxy`, env-привязка). External-сеть `reverse-proxy`.
- [ ] Создан/обновлён **`docker/docker-compose.prod.yml`** (вариант A): app + postgres, **`5432` НЕ пробрасывается наружу** (только внутренняя compose-сеть), app подключается к external-сети `reverse-proxy` и объявляет `VIRTUAL_HOST`/`LETSENCRYPT_HOST`/`LETSENCRYPT_EMAIL` + `DB_SYNCHRONIZE=false` + `CORS_ORIGIN`. `docker-compose.yml` (dev) — остаётся с пробросом `5432` и без reverse-proxy. Ansible использует `docker-compose.prod.yml`.
- [ ] `README.md` в `ansible/` покрывает:
  1. Сборка архива на ПК: `tar --exclude=node_modules --exclude=dist --exclude=logs --exclude=data --exclude=.git --exclude=playwright-report --exclude=test-results -czf vibesetup.tar.gz .` (исходники, **сборка идёт на сервере** внутри Docker).
  2. Передача по sftp (`sftp root@{{ server_ip }}`, `put vibesetup.tar.gz /opt/`).
  3. Запуск на сервере: `cd /opt/vibesetup/ansible && ansible-playbook playbook.yml` (или `-e @vars.yml`). Указать, что ansible ставится на сервере (`apt install ansible` / pip).
  4. Переменные и где их заполнять (`group_vars/all.yml` / `vars.yml`, секреты через `ansible-vault`).
  5. Мульти-проект: nginx-proxy поднимается один раз (тег `proxy`), последующие проекты на том же сервере повторно используют external-сеть `reverse-proxy` (указать, как добавить второй проект).
  6. Проверка здоровья + логи (`docker compose -f docker-compose.prod.yml logs -f app`).
- [ ] Плейбук **запускается на сервере** (`ansible_connection=local`) — нигде не подразумевает SSH с ПК разработчика на сервер. В README явно написано: «этот ansible запускается на целевом сервере, не на машине разработчика».
- [ ] Идемпотентность: повторный запуск `playbook.yml` не ломает работающее приложение (не пересоздаёт БД, не перевыпускает сертификат, не поднимает второй nginx-proxy, `docker compose up -d` безопасен). Тег `proxy` проверяет существование `reverse-proxy` сети/контейнеров перед поднятием.
- [ ] Интеграция с задачей 03: прод-env содержит `DB_SYNCHRONIZE=false` → при старте Nest накатывает миграции. `Dockerfile` копирует миграции в `dist/migrations`. Если задача 03 ещё не выполнена — оставить `DB_SYNCHRONIZE` в шаблоне и отметить зависимость.
- [ ] Docker compose: прод использует **`docker-compose.prod.yml`** (app + postgres, `5432` не наружу, external-сеть `reverse-proxy`, `VIRTUAL_HOST`/`LETSENCRYPT_*`). Dev `docker-compose.yml` не трогается.
- [ ] Документация: обновить `docs/deployment.md` и `GETTING_STARTED.md` разделом «Деплой через ansible (запуск на сервере)» со ссылкой на `ansible/README.md`; описать nginx-proxy-паттерн и мульти-проект. Делегировать `@docs-maintainer`.
- [ ] `AGENTS.md`: добавить в карту проекта папку `ansible/` и краткое описание; в Docker-разделе упомянуть `docker-compose.prod.yml` и nginx-proxy.

## Подсказки по реализации

- Не использовать SSH с ПК на сервер. Вся идея — локальный запуск ansible на сервере после sftp. `inventory.ini` → `localhost ansible_connection=local`.
- Установка Docker: официальный репозиторий `download.docker.com` (apt-ключ через `get_url` + `apt_repository`), пакет `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`. Использовать `docker compose` (v2, через plugin), не legacy `docker-compose`.
- Распаковка архива: `ansible.builtin.unarchive` с `src: "{{ archive_path }}"`, `dest: "{{ project_dir }}"`, `remote_src: yes`, формат `tar.gz` (исходники). **Сборка идёт на сервере** внутри Docker (`docker compose -f docker-compose.prod.yml build`) — multi-stage Dockerfile это поддерживает.
- `docker compose build`/`up -d` — модуль `community.docker.docker_compose_v2` (если установлен) ИЛИ `command: docker compose -f docker-compose.prod.yml ...` с `creates`/`changed_when`. Предпочтительнее `command` — меньше зависимостей на чистом сервере.
- **nginx-proxy (Q3=B):** образы `nginxproxy/nginx-proxy` + `nginxproxy/acme-companion`. Сеть `reverse-proxy` создаётся как **external** (в app-compose `networks.reverse-proxy.external: true`) — её создаёт proxy-compose. App-контейнер объявляет `VIRTUAL_HOST`/`LETSENCRYPT_HOST`/`LETSENCRYPT_EMAIL` в `environment` — nginx-proxy маршрутизирует, acme-companion выпускает сертификат. Один proxy на все проекты сервера (второй проект — тот же `reverse-proxy` + свой `VIRTUAL_HOST`). Certbot вручную НЕ ставится.
- Секреты в `group_vars/all.yml` — плейсхолдеры; в README — инструкция зашифровать через `ansible-vault encrypt vars.yml`. Не коммитить реальные пароли.
- Проверить, что `docker/Dockerfile` копирует миграции в `dist/migrations` (зависимость от задачи 03) — иначе prod не поднимется. Если задача 03 не сделана — добавить в README пометку «до деплоя выполнить задачу 03».
- Не запускать плейбук реально (нет сервера) — проверить синтаксис: `ansible-playbook playbook.yml --syntax-check` (если ansible установлен локально) ИЛИ отметить «проверка синтаксиса — при первом реальном запуске на сервере».

## Проверка

- `ansible-playbook ansible/playbook.yml --syntax-check` — без ошибок (если ansible доступен).
- `ansible-playbook ansible/playbook.yml --check --diff` (если есть ansible + сервер) — dry-run показывает planned changes без применения.
- Структура `ansible/` соответствует Acceptance; README пошагово описывает sftp архива + запуск на сервере + мульти-проект через общий nginx-proxy.
- В шаблоне env есть `DB_SYNCHRONIZE=false` (привязка к задаче 03), `VIRTUAL_HOST`/`LETSENCRYPT_HOST` (привязка к Q3=B).
- Есть `docker/docker-compose.prod.yml` без проброса `5432`, с external-сетью `reverse-proxy` (привязка к Q4=A).
- dev-серверы/e2e не запускать.