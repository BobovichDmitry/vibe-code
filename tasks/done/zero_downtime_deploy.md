Мигрировать сетап деплоя на подход деплоймента без простоя (0downtime): blue-green слоты backend (Nest) **и** frontend (Nuxt SSR), гибридная схема переключения, healthcheck + автоматический rollback + Telegram-нотификации. Референсы: `ai-provider` (swappable nginx upstream) и `tb-2026` (YAML-якоря, полные стеки-слоты).

> Финализировано из диалога (task-creator): гибридный вариант (c), оба сервиса без простоя, правим ВСЕ деплой-скрипты, уведомления через secret.yml-переменные.

---

## Контекст (анализ кода)

### Референс 1: `D:\work\projects\wormsoft\inside\ai-provider`

- **Blue-green backend-слоты** `node-blue`/`node-green` (плюс scheduler-слоты — у нас аналога нет, `scheduler` опускаем), активный цвет — в `.deploy-state/active-color`.
- **Nginx-сервис внутри compose** с runtime-swappable upstream: `docker/nginx/runtime/backend-upstream.conf` монтируется volume'ом; скрипт `scripts/update.sh` переписывает `server node-blue|green:3001` и делает `nginx -t && nginx -s reload` — переключение без разрыва соединений.
- **Порядок деплоя**: build standby → `wait_for_service_health` (healthcheck `/api/health` через `docker inspect`) → переключение upstream → `verify_active_backend` (wget через nginx) → останов старого слота (с `OLD_SLOT_STOP_DELAY`).
- **Rollback**: `fail_update` восстанавливает старый upstream и делает reload; старый слот в этот момент ещё жив.
- **Telegram-нотификации**: start-сообщение → edit в финальное (active slot, время) / setMessageReaction; отправка только если `BOT_TOKEN` + `TELEGRAM_NOTIFY_CHAT` заданы, иначе тихий пропуск.

### Референс 2: `D:\work\projects\wormsoft\clients\eventous\tb-2026\production\prod\`

- **YAML-якоря против дублирования**: `x-node-common` / `x-frontend-common` — описание сервисов одно; blue-слот называется просто `node`/`frontend`/`nginx`, green — суффикс `_green`.
- **Две изолированные сети** (`back_blue`/`back_green`) — оба слота имеют одинаковые aliases (`node`, `frontend`), т.е. nginx-конфиг/межсервисные ссылки пишутся на стабильные имена.
- **Слот = полный стек** (nginx + frontend + backend); переключение — на уровне внешнего host-nginx через `set $app_upstream http://127.0.0.1:81|82;`. **У нас этот уровень не применяется** (у нас внешний nginx-proxy, который не трогаем), но полные стеки-слоты + изолированные сети берём.

### Выбранная схема (гибрид, вариант «c»)

Один **nginx-сервис внутри нашего compose**, подключённый к `reverse-proxy` сети (VIRTUAL_HOST остаётся на нём), который маршрутизирует на два полных слота `frontend+backend`:

```
nginx-proxy (общий, не трогаем)
  └── edge-nginx (наш, в compose; VIRTUAL_HOST; runtime upstream-файл)
        ├── frontend-blue ← backend-blue    (сеть slot_blue)
        └── frontend-green ← backend-green   (сеть slot_green)
```

- Switch-файлы: `docker/nginx/runtime/frontend-blue upstream` и т.д.; edge-nginx держит два `upstream` (frontend, backend) в runtime-файле, переключаемом скриптом деплоя, либо один файл с обоими цветами.
- `NUXT_API_BASE` внутри каждого слота указывает на alias `backend:3001` своей сети (network aliases `frontend`/`backend` в обеих сетях, как в tb-2026) — Nitro-прокси /api/** идут в backend своего слота без участия edge-nginx.
- Альтернатива (допускается решающему): edge-nginx может проксировать и /api напрямую на backend-слот, минуя Nitro — тогда обновляется только upstream backend, но меняется текущая схема (`Nuxt` проксирует /api). Не переключать топологию без необходимости — меньше правок.

### Текущее состояние vibecode-setup (что правим)

- `docker/docker-compose.prod.yml` — единственный frontend + backend + postgres; сборка на сервере (ansible) или pull из Registry (CI, `FRONTEND_IMAGE`/`BACKEND_IMAGE`).
- `deploy.sh` — ручной деплой (ansible на сервере, сборка на сервере); `docker/deploy_ci.sh` — CI-деплой из Registry; **оба делают stop/replace → up с простоем**. Оба пишут маркеры `### DEPLOY-FINISHED/FAILED ###`.
- `.envs/<env>/public.yaml` + `secret.enc.yaml` — деплой-переменные (generic pass-through в `docker/env`), секреты через SOPS+age (`scripts/decrypt.sh`).
- `ansible/roles/app` — роль деплоя приложения (тоже поднимает compose; при необходимости обновить шаблоны).
- Healthcheck backend'а: `/api/health` отсутствует? Проверить — в ai-provider/tb-2026 healthcheck бьёт `GET /api/health`. В Nest у нас есть только `GET /api/version` — **вероятно, нужно добавить** `GET /api/health` (без авторизации) как lightweight-эндпоинт.

## Acceptance criteria

1. **Новый prod compose** (`docker-compose.prod.yml`): YAML-якоря для frontend/backend; слоты `frontend-blue`/`backend-blue` и `frontend-green`/`backend-green` (blue может без суффикса — по вкусу решающему, главное — отсутствие дублирования); изолированные сети `slot_blue`/`slot_green` с одинаковыми aliases `frontend`/`backend`; общий `postgres` в обеих сетях; edge-nginx-сервис с VIRTUAL_HOST и runtime-swappable upstream-файлом (volume, как в ai-provider); healthcheck у обоих backend-слотов.
2. **Backend healthcheck-эндпоинт**: `GET /api/health` (public, без JWT) — для healthcheck'ов compose и скрипта деплоя.
3. **Скрипт деплоя 0downtime** (обновить `docker/deploy_ci.sh` и путь через `deploy.sh`/ansible — вся цепочка деплоя должна быть бесшовной):
   - состояние активного слота в файле (`.active-slot` / `.deploy-state/active-color`);
   - порядок: определить standby-слот → pull/build образов standby → `up -d` standby → ждать healthcheck backend'а → переключить upstream edge-nginx (reload) → верификация через edge-nginx → записать новое состояние → остановить старый слот (с задержкой, `OLD_SLOT_STOP_DELAY`);
   - **rollback**: при любой ошибке — вернуть старый upstream + reload, старый слот не останавливать; деплой завершается маркером `### DEPLOY-FAILED ... ###`;
   - первый (bootstrap) деплой на пустом сервере: поднимает оба слота, активирует blue;
   - сохранить финальные маркеры `### DEPLOY-FINISHED/FAILED ... ###` в stdout и лог.
4. **Telegram-нотификации**: переменные `BOT_TOKEN` и `TELEGRAM_NOTIFY_CHAT` (опционально `TELEGRAM_NOTIFY_TOPIC`) читаются из расшифрованных `.envs/<env>/secret.yaml` (плюс их можно прописать в `secret.yaml.example` в комментариях); если обе заданы — отправлять start/finish/failed уведомления (по образцу `update.sh` из ai-provider: старт-сообщение → edit в финал с активным слотом и временем, реакция 👍 на успех); если нет — пропускать молча. **Не разносить секреты в public.yaml.**
5. **Документация**: обновить `docs/deployment.md`, `ansible/README.md` и раздел «Build & Prod» корневого `AGENTS.md` под новую схему (как деплой работает, как переключаются слоты, как откатиться).
6. Dev-сетап (`docker-compose.yml`) не ломать — blue-green касается prod/CI-деплоя.

## Подсказки по реализации

- Скрипт деплоя взять за основу `update.sh` из ai-provider (порядок/rollback/healthcheck/telegram) и YAML-структуру compose — из tb-2026 (`docker-compose-prod.yml`: якоря, суффиксы, сети, aliases, healthcheck).
- Edge-nginx конфиг: простая пара `upstream` + `location /` (→ frontend-слот) + `location /api` (→ backend-слот, опционально), upstream-файл в `docker/nginx/runtime/`, монтируется volume'ом.
- Слоты и nginx-proxy: `edge-nginx` единственный подключён к `reverse-proxy` с `VIRTUAL_HOST`/`LETSENCRYPT_*`; слоты наружу не торчат (`expose`, не `ports`).
- Frontend (Nitro): каждый слот задаёт `NUXT_API_BASE: http://backend:3001/api` через network alias своей сети — alias решает, какой backend используется, без изменения hostname'ов.
- `/api/health` в backend: простой `@Get('health')` без guard — по образцу `/api/version` (`HealthController` или добавить в существующий public-контроллер).
- Telegram: парсить переменные из секретов так же, как `deploy_ci.sh` уже мёржит public+secret → `docker/env`; с этими переменными экспортировать в окружение скрипта деплоя.
- Конкурентные деплои: использовать `flock` на lock-файл в CI-скрипте, чтобы два деплоя подряд не гонялись (опционально, по образцу иных скриптов в проекте).

## Проверка

- `npm run build:backend && npm run build:frontend` — без ошибок.
- `bash -n deploy.sh docker/deploy_ci.sh` — синтаксис.
- E2e не запускать; после реализации проверяется вручную пользователем через `./.ci-bundle` или тестовый деплой.
- Проверить вручную наличие `/api/health` на dev-сервере backend'а (`curl http://localhost:3001/api/health`).

## Уточнения из диалога (2026-09-09)

1. Схема — гибрид: edge-nginx в compose между nginx-proxy и слотами, nginx-proxy не трогаем. ✅
2. Frontend (Nuxt) тоже переключается без простоя. ✅
3. Мигрируем оба деплоя: `deploy.sh` (ansible) и `docker/deploy_ci.sh` — везде 0downtime. ✅
4. Telegram-нотификации: читать `BOT_TOKEN`/`TELEGRAM_NOTIFY_CHAT` (и опционально `TELEGRAM_NOTIFY_TOPIC`) из `.envs/<env>/secret.yaml`; есть — отправлять, нет — пропускать. ✅

---

## Реализация (2026-09-09)

- **Backend**: новый публичный эндпоинт `GET /api/health` (`apps/backend/src/health/` — HealthController + HealthModule, зарегистрирован в AppModule). `npx tsc --noEmit` — без ошибок.
- **Prod-архитектура (blue-green)**: `docker/docker-compose.prod.yml` переписан — edge-nginx (nginx:1.27-alpine, единственный в reverse-proxy, VIRTUAL_HOST) → слоты `frontend-blue/green` + `backend-blue/green` через YAML-якоря `x-frontend-common`/`x-backend-common`; сети `slot_blue`/`slot_green` с одинаковыми aliases `frontend`/`backend`; postgres общий; healthcheck'и обоих сервисов слота. Nitro слота проксирует /api/** на alias `backend` своей сети.
- **Edge-nginx**: `docker/nginx/conf.d/edge.conf` (proxy_pass → upstream app_frontend) + runtime-файл `docker/nginx/runtime/upstream-frontend.conf` (переключается деплоем, reload без разрыва соединений).
- **`docker/deploy_0downtime.sh`** (новый, запускается на сервере): build/pull standby → postgres up + health → standby-слот up + healthcheck → переключение upstream (`nginx -t` + reload) → верификация /api/health через edge-nginx → запись `.active-slot` → остановка старого слота (OLD_SLOT_STOP_DELAY=10с). Rollback при любой ошибке (upstream возвращается на активный слот). Bootstrap при отсутствии .active-slot. Telegram-нотификации (BOT_TOKEN/TELEGRAM_NOTIFY_CHAT/TELEGRAM_NOTIFY_TOPIC из docker/env; есть — отправляются, нет — молча пропускаются).
- **Ansible**: роль app переписана — готовит окружение (env, образы в docker/.env, postgres up + pg_isready + синхронизация пароля роли ДО старта слотов — restart backend'а больше не нужен) и вызывает `./deploy_0downtime.sh <project> --pull|--build`. Healthcheck playbook — через edge-nginx. В group_vars добавлены отсутствовавшие `prod_compose_file` и `cors_origin` (латентный баг). Пропатчены оба деплой-пути: `deploy.sh` и `docker/deploy_ci.sh` идут через ansible → deploy_0downtime.sh.
- **Env/docs**: `.envs/*/secret.yaml.example` — закомментированные Telegram-переменные; `.gitignore` + `docker/.active-slot`; документация синхронизирована docs-maintainer'ом (docs/deployment.md, docs/areas/blue-green-deploy.md (новый), ansible/README.md, AGENTS.md, backend-api-structure.md, ci-deployment.md, context-index.md).

## Проверка

- `npx tsc --noEmit` (backend) — OK; `docker compose config` нового prod-compose — OK; `bash -n` deploy.sh / deploy_ci.sh / deploy_0downtime.sh — OK.
- E2e не запускались (правила проекта); реальный деплой проверяется пользователем на тестовом стенде.

## Остаточные риски

- edge-nginx при reboot сервера может стартовать до слота (nginx не резолвит upstream) — но `restart: unless-stopped` поднимет его после старта слота.
- Blue-green проверен синтаксически/конфигурационно, но не на живом деплое — первый тестовый деплой показать пользователю.

---

## Дополнение: доводка на живом проде (2026-09-04)

Blue-green схема доведена до рабочего состояния через локальный деплой (`deploy_local.sh`, минуя CI). Найдено и исправлено в процессе:

1. **CI-деплой не запускался**: в GitLab не были заданы `SOPS_AGE_KEY_TEST/PRODUCTION` (прописал пользователь).
2. **`ensure_sops_yq`**: `/opt/binaries/sops` на раннере — папка (у директорий `-x` истинен) → symlink на папку → `command -v` проваливался. Теперь только обычный файл + проба запуска `--version`, копия вместо symlink.
3. **`yml_str`**: однострочник с `${s//\"/\}` — синтаксическая ошибка bash на Linux (парсинг падал на дальней `(`). Развернута в многострочную, проверена на сервере.
4. **tar-исключения `--exclude=tasks`** вырезали `ansible/roles/*/tasks/` — роли ansible не обновлялись на сервере со времён d38d343 («no such service: frontend»). Все корневые исключения заякорены `./`.
5. **`proxy_compose_file`/`cors_origin`/`prod_compose_file`** — отсутствовавшие переменные group_vars (плейбук падал).
6. **YAML**: `name:` с незакавыченным `CI: pull` — parse error ansible.
7. **Синхронизация пароля PG**: heredoc+jinja ломал парсер ansible 2.16 → `echo SQL | psql -v pw=...` (интерполяция `:'pw'` работает только в stdin, не в `-c`).
8. **`extra_env: null`** при пустых ключах (локальный деплой без CI-переменных) → `env.j2` падал на `.items()`. Фикс: `default({}, true)` + `extra_env: {}`.
9. **Healthcheck'и слотов**: `localhost` → `::1` в alpine (Nitro слушает IPv4) → вечно unhealthy. Заменено на `127.0.0.1`.
10. **Bind-mount inode-ловушка**: file-mount nginx-конфигов + tar-распаковка (новые inode) → nginx видел устаревший upstream, 502 после остановки старого слота. Монтируются каталоги `conf.d/` и `runtime/`.
11. **Bootstrap**: upstream пишется в реально поднимаемый слот ДО старта edge-nginx + `--force-recreate` (up -d не пересоздаёт рестарт-луп); rollback в bootstrap пишет standby.
12. **Keepalive edge→Nitro**: nginx map `'' → ''` (не close) — иначе мёртвые сокеты в пуле → чередование 200/400.
13. **Windows-совместимость deploy_ci.sh**: temp-файл вместо process substitution (нативный yq.exe), early-return `ensure_sops_yq` при готовых инструментах; `deploy_local.sh` скачивает sops/yq в `.tools/`.
14. **Легаси-контейнеры** старой схемы (frontend/backend) удаляются в конце успешного деплоя (двойной VIRTUAL_HOST у nginx-proxy).

CI на время отладки отключён (`workflow: when: never` в .gitlab-ci.yml — вернуть при необходимости). Ручной деплой описан в корневом AGENTS.md (deploy_local.sh + отладка на сервере).

Итоговое состояние прода: active-slot green, `/api/health` 200, `/api/version` 200, `/api/users/count` 200, корень 200 — три полных цикла деплоя (bootstrap → blue → green) без простоя.
