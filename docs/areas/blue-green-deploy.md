# Blue-green деплой без простоя (prod)

Prod-деплой построен по **blue-green-схеме** — обновление приложения без простоя.

## Компоненты (`docker-compose.prod.yml`)

- **edge-nginx** (`nginx:1.27-alpine`) — единственный сервис с `VIRTUAL_HOST`
  в сети `reverse-proxy`. Конфиг: `docker/nginx/conf.d/edge.conf` (`proxy_pass`
  на upstream `app_frontend`). Runtime-файл
  `docker/nginx/runtime/upstream-frontend.conf` задаёт, какой слот обслуживает
  трафик (`server frontend-blue:3000;` или `frontend-green:3000;`) — переключение
  upstream + `nginx -s reload` = смена слота **без разрыва соединений**.
- **frontend-blue / backend-blue** и **frontend-green / backend-green** — два
  слота, определяются YAML-якорами `x-frontend-common` / `x-backend-common`.
  Каждый слот живёт в своей изолированной сети (`slot_blue` / `slot_green`),
  внутри которой у frontend/backend одинаковые aliases `frontend` / `backend` —
  Nitro слота проксирует `/api/**` → `http://backend:3001/api`. Порты наружу
  не проброшены.
- **postgres** — общий для обоих слотов.
- Healthcheck'и: backend — `GET /api/health`, frontend — `/`.

## Алгоритм деплоя (`docker/deploy_0downtime.sh`)

Скрипт запускается **на сервере** из каталога `docker/` (вызывается
ansible-ролью `app`):

```bash
./deploy_0downtime.sh <project_name> --build   # сборка на сервере (ручной deploy.sh)
./deploy_0downtime.sh <project_name> --pull    # образы из Registry (CI)
```

1. Активный слот читается из `docker/.active-slot` (gitignored). Если файла нет
   (первый деплой, **bootstrap**) — поднимается только новый слот, старый
   не останавливается.
2. Build/pull standby-слота.
3. Postgres up + ожидание healthcheck.
4. Standby-слот up + healthcheck'и (backend `/api/health`, frontend `/`).
5. Переключение upstream: edge-nginx `nginx -t` + reload (без разрыва соединений).
6. Верификация `/api/health` через edge-nginx.
7. Запись нового активного слота в `docker/.active-slot`.
8. Остановка старого слота с задержкой `OLD_SLOT_STOP_DELAY`
   (по умолчанию 10с).

**Rollback**: любая ошибка → upstream переключается обратно на активный слот
(`fail_deploy`), старый слот не трогается.

## Telegram-нотификации деплоя

Если в `docker/env` заданы `BOT_TOKEN` + `TELEGRAM_NOTIFY_CHAT` (опционально
`TELEGRAM_NOTIFY_TOPIC`) — скрипт отправляет start-сообщение, затем
редактирует его в итог (активный слот, время, результат) и ставит реакцию 👍.
Если переменные не заданы — пропускаются молча. Переменные идут через
generic pass-through (см. `docs/deployment.md`), закомментированные —
в `.envs/<env>/secret.yaml.example`.

## Связанное

- Ansible-роль `app` и playbook — `ansible/README.md`
- Общий деплой/CI — `docs/deployment.md`, `docs/areas/ci-deployment.md`
- `GET /api/health` — `docs/areas/backend-api-structure.md`
