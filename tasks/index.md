# Tasks Index

Источник истины и порядка задач — этот файл (см. `tasks/agents.md`). Порядок — сверху вниз в разделе **Todo**. Крупные задачи пронумерованы префиксом — выполнять по номеру.

## Todo
1. [04_admin_panel_horizontal_menu.md](todo/04_admin_panel_horizontal_menu.md) — рестайл админ-панели под дизайн-систему agent-hosted (useBranding, ThemeToggle.vue, шапка с бренд-блоком, иконки) с **горизонтальным** меню + публичный `GET /api/branding` (env `BRAND_TITLE`/`BRAND_FAVICON_URL`)
2. [05_ansible_local_deploy.md](todo/05_ansible_local_deploy.md) — ansible НА сервере: Docker/compose + общий nginx-proxy+acme (мульти-проект) + `docker-compose.prod.yml` (без `5432` наружу) + сборка из архива исходников (переменные: IP, домен)

## NeedInfo
<!-- задачи, ожидающие ответа. Вопросы — внутри файла (и в корневом questions.md) -->

## Errors
<!-- задачи, которые не удалось решить технически -->

## Done
<!-- выполненные задачи. Файл перенесён в done/, детали — внутри файла -->
- [01_transfer_task_mechanics.md](done/01_transfer_task_mechanics.md) — перенести механику очереди задач из agent-hosted: папка `tasks/` + 4 скилла + сабагенты code-solver/e2e-writer (оба стиля e2e) + доработка e2e-инфры (2025-01-24)
- [02_strip_business_functionality.md](done/02_strip_business_functionality.md) — убрать бизнес-функционал (reminders + telegram-settings), оставить голый каркас: auth + users + public user-count + `create-admin` (2025-01-25)
- [03_db_migrations_dual_mode.md](done/03_db_migrations_dual_mode.md) — два режима БД (dev `synchronize`, prod миграции): `DB_SYNCHRONIZE`, `data-source.ts`, baseline-миграция, npm-скрипты `migration:*`/`db:recreate` (2025-01-25)