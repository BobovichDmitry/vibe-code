# Ansible-деплой VibeSetup UI (запуск НА сервере)

Этот ansible **запускается на целевом сервере**, не на машине разработчика.
Разработчик только собирает архив исходников и передаёт его на сервер по sftp.

## Предварительные требования

- Целевой сервер: Debian/Ubuntu с root-доступом
- Ansible установлен на сервере: `apt install ansible` (или `pip install ansible`)
- Доменное имя с DNS-записью, указывающей на IP сервера

## Шаг 1. Собрать архив исходников (на ПК разработчика)

```bash
cd vibe-setup-ui
tar --exclude=node_modules \
    --exclude=dist \
    --exclude=logs \
    --exclude=data \
    --exclude=.git \
    --exclude=playwright-report \
    --exclude=test-results \
    -czf my-project.tar.gz .
```

> Сборка приложения (frontend + backend) идёт **на сервере** внутри Docker
> (multi-stage Dockerfile). В архиве — только исходники, без `node_modules`/`dist`.

## Шаг 2. Передать архив на сервер по sftp

```bash
sftp root@<server_ip>
sftp> put my-project.tar.gz /opt/
sftp> exit
```

## Шаг 3. Запустить ansible на сервере

```bash
# Подключиться к серверу
ssh root@<server_ip>

# Установить ansible (если ещё не установлен)
apt update && apt install -y ansible

# Перейти в папку с ansible-скриптами
# (ansible/ — часть репозитория, значит уже в архиве)
cd /opt/my-project/ansible

# Заполнить переменные (скопировать пример → отредактировать → зашифровать)
cp vars.example.yml vars.yml
# Отредактируйте vars.yml: domain, db_password, jwt_secret, admin_password, letsencrypt_email
ansible-vault encrypt vars.yml

# Запустить плейбук
ansible-playbook playbook.yml -e @vars.yml
```

Или отдельные теги:

```bash
# Только установка Docker
ansible-playbook playbook.yml --tags deps -e @vars.yml

# Только nginx-proxy (один раз на сервере)
ansible-playbook playbook.yml --tags proxy -e @vars.yml

# Только деплой приложения (после обновления архива)
ansible-playbook playbook.yml --tags deploy -e @vars.yml

# Проверка здоровья
ansible-playbook playbook.yml --tags healthcheck -e @vars.yml
```

## Переменные

Переменные заполняются в `group_vars/all.yml` (плейсхолдеры) или в `vars.yml`
(реальные значения, рекомендуется `ansible-vault encrypt vars.yml`).

| Переменная | Описание | Пример |
|------------|----------|--------|
| `server_ip` | IP-адрес сервера | `203.0.113.10` |
| `domain` | Домен приложения | `app.example.com` |
| `project_dir` | Путь распаковки исходников | `/opt/my-project` |
| `archive_path` | Путь к архиву на сервере | `/opt/my-project.tar.gz` |
| `proxy_dir` | Путь к nginx-proxy compose | `/opt/nginx-proxy` |
| `db_username` | PostgreSQL пользователь | `my-project` |
| `db_password` | PostgreSQL пароль | (секрет) |
| `db_name` | PostgreSQL база | `my-project_db` |
| `jwt_secret` | JWT-секрет | (секрет, 32+ байт) |
| `admin_login` | Логин первого админа | `admin` |
| `admin_password` | Пароль первого админа | (секрет) |
| `brand_title` | Заголовок бренда | `VibeSetup UI` |
| `brand_favicon_url` | URL favicon | `/favicon.svg` |
| `letsencrypt_email` | Email для Let's Encrypt | `devops@example.com` |

Секреты (`db_password`, `jwt_secret`, `admin_password`) — **обязательно**
зашифровать через `ansible-vault`. Не коммитьте `vars.yml` с реальными паролями.

## Мульти-проект (несколько приложений на одном сервере)

nginx-proxy + acme-companion поднимаются **один раз** на сервере (тег `proxy`).
Каждый проект-контейнер подключается к external-сети `reverse-proxy` и объявляет
свой `VIRTUAL_HOST`/`LETSENCRYPT_HOST`.

Чтобы добавить второй проект:

1. Распакуйте архив второго проекта в `/opt/project2/`.
2. Создайте `docker/env` с `VIRTUAL_HOST=project2.example.com` и другими переменными.
3. В `docker-compose.prod.yml` второго проекта укажите `networks.reverse-proxy.external: true`.
4. `docker compose -f docker-compose.prod.yml up -d` — nginx-proxy автоматически
   начнёт маршрутизировать трафик на новый контейнер по домену.
5. acme-companion выпустит Let's Encrypt-сертификат для нового домена.

> **Не запускайте тег `proxy` повторно** для второго проекта — общий nginx-proxy
> уже поднят. Повторный запуск безопасен (идемпотентен), но не нужен.

## Проверка здоровья и логи

```bash
# Healthcheck через ansible
ansible-playbook playbook.yml --tags healthcheck -e @vars.yml

# Логи приложения
cd /opt/my-project/docker
docker compose -f docker-compose.prod.yml logs -f frontend backend

# Логи nginx-proxy
cd /opt/nginx-proxy
docker compose -f compose-proxy.yml logs -f nginx-proxy

# Проверка вручную (frontend edge на 3000 за nginx-proxy)
curl http://localhost:3000/api/users/count
# Ожидается: {"total":1,...} (HTTP 200)
# Или напрямую в backend (внутренний, 3001):
# docker compose -f docker-compose.prod.yml exec backend wget -qO- http://localhost:3001/api/users/count

curl https://<domain>/api/users/count
# После выпуска сертификата — HTTP 200
```

## Идемпотентность

Повторный запуск `ansible-playbook playbook.yml` безопасен:
- Docker не переустанавливается (apt state=present)
- nginx-proxy не пересоздаётся (проверка существования контейнера)
- Деплой идёт через `docker/deploy_0downtime.sh` (blue-green, без простоя) —
  поднимается только standby-слот, затем переключается edge-nginx upstream
- БД (PostgreSQL volume) не пересоздаётся
- Сертификаты Let's Encrypt не перевыпускаются (acme-companion управляет этим)

## Деплой без простоя (blue-green)

Роль `app` **не** делает `docker compose up -d` напрямую. Она готовит окружение:

- рендер `docker/env` (в CI-режиме — `FRONTEND_IMAGE`/`BACKEND_IMAGE`);
- поднимает postgres и ждёт готовности (`pg_isready`);
- синхронизирует пароль роли (`ALTER USER`, idempotent) **до старта слотов** —
  рестарт backend после синхронизации не нужен;

…затем вызывает `docker/deploy_0downtime.sh <project_name> --pull` (CI)
или `--build` (ручной `deploy.sh`). Скрипт поднимает standby-слот
(frontend-blue/backend-blue или frontend-green/backend-green), проверяет
healthcheck'и, переключает upstream edge-nginx (`nginx -t` + reload) и
останавливает старый слот. Подробности — `docs/deployment.md`.

В `group_vars/all.yml` определены `prod_compose_file: "docker-compose.prod.yml"`
и `cors_origin: "https://{{ domain }}"`. Healthcheck в playbook.yml выполняется
через edge-nginx: `docker compose exec -T edge-nginx wget -qO- http://127.0.0.1/api/users/count`.

## Структура ansible/

```
ansible/
  ansible.cfg              # Конфиг: inventory, host_key_checking=False
  inventory.ini            # localhost, ansible_connection=local
  group_vars/all.yml       # Переменные (плейсхолдеры)
  vars.example.yml         # Пример заполнения (для копирования)
  playbook.yml             # Основной плейбук (tags: deps, proxy, deploy, healthcheck)
  roles/
    docker/                # Установка Docker + compose-plugin
    nginx_proxy/           # Поднятие общего nginx-proxy + acme-companion
    app/                   # Распаковка, env, postgres, вызов docker/deploy_0downtime.sh
  templates/
    env.j2                 # Шаблон docker/env (прод-env)
    compose-proxy.yml.j2   # docker-compose для nginx-proxy + acme
  README.md                # Этот файл
```

## Зависимости

- **Задача 03** (миграции): выполнена. `DB_SYNCHRONIZE=false` в прод-env →
  Nest.js накатывает миграции при старте. Dockerfile копирует `dist/migrations/`.
- **Задача 04** (брендинг): выполнена. Переменные `BRAND_TITLE`/`BRAND_FAVICON_URL`
  в шаблоне env.