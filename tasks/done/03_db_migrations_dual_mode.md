Перевести БД в двухрежимную работу по образцу `agent-hosted`: локально — `synchronize: true` (быстрая итерация), на проде — миграции (TypeORM, `migrationsRun: true`, автозапуск pending при старте Nest). Режим переключается одной env-переменной `DB_SYNCHRONIZE`.

> **Решения по вопросам:** Q5 — порядок выполнения 01→02→**03**→04→05; задача 03 выполняется строго **после 02** (baseline-миграция описывает финальный набор сущностей каркаса без reminders/settings), независимо от 01/04.

---

## Контекст (анализ кода)

Сейчас `apps/backend/src/database/database.module.ts` жёстко `synchronize: true`, миграций нет. `ENTITIES` определён прямо в `database.module.ts` (после задачи 02 там останется только `UserEntity`, возможно `AdminEntity`). `apps/backend/src/database/reset-db.ts` — standalone-скрипт `db:reset` через `dataSource.synchronize(true)`, подключает только `UserEntity`. Отдельной сущности-списка `ENTITIES` и standalone `data-source.ts` для CLI нет.

Референс `agent-hosted` реализует паттерн (см. `docs/migrations.md` в референсе):

- `apps/backend/src/database/database.module.ts` — `parseBooleanEnv(process.env.DB_SYNCHRONIZE, true)` → `synchronize`; `migrationsRun = !synchronize`; `migrations: [join(__dirname, '..', 'migrations', '*.{ts,js}')]`.
- `apps/backend/src/database/entities.ts` — единый `ENTITIES` (общий для Nest-модуля и standalone DataSource).
- `apps/backend/src/data-source.ts` — standalone `DataSource` для TypeORM CLI (`synchronize: false`, `migrationsRun: false`, тот же `ENTITIES`, `migrations: [__dirname + '/migrations/*.{ts,js}']`).
- `apps/backend/src/migrations/<timestamp>-InitSchema.ts` — **baseline**-миграция: создаёт всю схему всех сущностей одной миграцией, **диалект-агностик** (Table API + ветвление по `connection.options.type` для boolean-default `false`/`0` и т.п.).
- `apps/backend/src/database/recreate-db.ts` — `db:recreate` (дроп схемы + накат миграций с нуля, prod-prep).
- npm-скрипты в `apps/backend/package.json`: `typeorm`, `migration:generate`, `migration:create`, `migration:run`, `migration:revert`, `db:recreate` (и зеркально в root `package.json`).
- `docs/migrations.md` — документация двух режимов + prod-prep цикл проверки дрейфа (`db:recreate` → `migration:generate` должен дать «No changes»).

Целевой прод-диалект — PostgreSQL; SQLite — локально/e2e. Существующих прод-БД нет — миграции применяются к свежим БД (усыновление старых схем не нужно).

## Acceptance criteria

- [ ] В `apps/backend/.env` (и `docker/env`, `docker/prod.env.example` после задачи 05) добавлена переменная `DB_SYNCHRONIZE` с дефолтом `true` для dev и `false` для prod.
- [ ] `database.module.ts`: `synchronize = parseBooleanEnv(DB_SYNCHRONIZE, true)`; `migrationsRun = !synchronize`; подключены `ENTITIES` (из нового `entities.ts`) и `migrations` (glob `join(__dirname, '..', 'migrations', '*.{ts,js}')`). Работает и в dev (`ts-node`: `src/migrations/`), и в prod (`node dist/main`: `dist/migrations/`).
- [ ] Создан `apps/backend/src/database/entities.ts` с единым `ENTITIES` (после задачи 02 — только оставшиеся сущности каркаса). И `database.module.ts`, и `data-source.ts`, и `reset-db.ts` импортируют `ENTITIES` оттуда (убрать дублирование).
- [ ] Создан `apps/backend/src/data-source.ts` (standalone DataSource для TypeORM CLI, `synchronize:false`, `migrationsRun:false`, оба диалекта через `DB_TYPE`).
- [ ] Создана папка `apps/backend/src/migrations/` и **baseline**-миграция `<timestamp>-InitSchema.ts`, создающая всю схему каркаса (таблица `user` + всё, что описывают оставшиеся сущности) за одну миграцию. Диалект-агностик: boolean-default ветвится Postgres `false` / SQLite `0`; для остального — Table API (без голого SQL-ветвления). Проверено: пустой diff против свежей БД (prod-prep цикл).
- [ ] Создан `apps/backend/src/database/recreate-db.ts` (`db:recreate`: initialize → drop schema / `DROP TABLE` cascade → run pending migrations → destroy). Отказывает на дефолтном dev-SQLite (`./data/database.sqlite`) — только по `DB_*` env (как в референсе).
- [ ] `apps/backend/package.json`: добавлены скрипты `typeorm`, `migration:generate`, `migration:create`, `migration:run`, `migration:revert`, `db:recreate`. Root `package.json`: зеркально `migration:*` / `db:recreate` через `--workspace=apps/backend`.
- [ ] `reset-db.ts` (`db:reset`) — переделан/оставлен как dev-утилита (synchronize), но использует общий `ENTITIES` (не хардкод `UserEntity`).
- [ ] e2e: изолированная БД (`e2e/.env` / `global-setup.ts`) остаётся на `synchronize` (миграции в e2e не прогоняются — скорость/стабильность). Если в e2e свой `DB_SQLITE_PATH` — `DB_SYNCHRONIZE=true` там явно.
- [ ] Docker: `docker/Dockerfile` копирует `apps/backend/src/migrations` ИЛИ собирает их в `dist/migrations` через `nest build` (проверить `nest-cli.json`/`tsconfig` — `migrations` должны попасть в `dist`). `database.module.ts` резолвит `dist/migrations` через `__dirname/..`. Prod-запуск накатывает миграции при старте.
- [ ] `docker/env` / `docker-compose.yml`: прод-режим `DB_SYNCHRONIZE=false` (env-файл), dev-`docker-compose` может оставить дефолт `true`. PostgreSQL в compose остаётся.
- [ ] Документация: создан `docs/migrations.md` (по образцу референса — таблица режимов, файлы, npm-скрипты, prod-prep цикл, «как добавить изменение схемы»); обновлены `docs/areas/database-structure.md`, `docs/deployment.md`, `GETTING_STARTED.md` (упомянуть `DB_SYNCHRONIZE` и миграции). Делегировать `@docs-maintainer`.
- [ ] `AGENTS.md`: в таблице env добавить `DB_SYNCHRONIZE`; в разделе «Key Design Decisions» обновить пункт 3 про БД (добавить двухрежимность).

## Подсказки по реализации

- Сначала выполнить задачу 02 (каркас), иначе baseline-миграция опишет reminders/settings, которые потом удалят — придётся переписывать.
- Baseline: взять за основу структуру `1785414832573-Init.ts` из референса (Table API + `queryRunner.manager.query` для индексов), но ОГРАНИЧИТЬ таблицами каркаса (`user` и т.п.). Имя класса — осмысленное (`InitSchema`), таймстемп в имени файла — текущий.
- Boolean-default ветвление по `connection.options.type`: `type === 'sqlite'` → `false` литерал через `queryRunner.query("...DEFAULT 0")` или Table-column `default: false` для sqlite; для postgres `default: false`. В референсе — см. `AddCronTaskOneShotReminder` для паттерна.
- `nest-cli.json` / `tsconfig.build.json`: убедиться, что `src/migrations/**` попадает в `dist` (часто нужно убрать исключение `migrations` из `exclude` или добавить в `include`). Иначе prod не найдёт миграции.
- Не запускать dev-серверы/e2e. Проверка типов — `tsc --noEmit`. Prod-prep цикл (`db:recreate` + `migration:generate`) можно запустить только если есть локальный postgres — иначе отметить как «проверено на sqlite, postgres-цикл — в задаче 05/при деплое».

## Проверка

- `cd apps/backend && npx tsc --noEmit` — без ошибок.
- `cd apps/backend && DB_TYPE=sqlite DB_SQLITE_PATH=./data/test-mig.sqlite npm run migration:run` — накатывает baseline без ошибок; `migration:revert` — откатывает.
- (Если есть локальный postgres) `DB_TYPE=postgres DB_HOST=... npm run db:recreate` → `npm run migration:generate -- src/migrations/_check` → «No changes»; удалить `_check`.
- `npm run build:backend` → `ls apps/backend/dist/migrations` содержит скомпилированные миграции.
- dev-сервер с `DB_SYNCHRONIZE=true` (по умолчанию) стартует без запуска миграций (пользователь проверит).