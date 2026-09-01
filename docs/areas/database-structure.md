# Database Structure

## Описание

TypeORM с двумя подключениями: SQLite (dev) / PostgreSQL (prod). Два режима работы:
- **Dev**: `DB_SYNCHRONIZE=true` → `synchronize: true` (быстрая итерация, миграции не запускаются).
- **Prod**: `DB_SYNCHRONIZE=false` → `synchronize: false`, `migrationsRun: true` (pending-миграции накатываются при старте Nest).

Для PostgreSQL перед инициализацией TypeORM backend автоматически создаёт `DB_DATABASE`, если её нет (см. [Автосоздание БД](#автосоздание-бд-postgres)).

Сущности: User (авторизация/управление) и File (мета файлов в S3).

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/database/database.module.ts` | TypeORM config (SQLite/PostgreSQL via DB_TYPE, режимы via DB_SYNCHRONIZE) |
| `apps/backend/src/database/ensure-database.ts` | Автосоздание БД при старте (только postgres): проверяет `DB_DATABASE` через системную базу `postgres`, создаёт при отсутствии |
| `apps/backend/src/database/entities.ts` | Единый `ENTITIES` — общий для Nest-модуля, DataSource и reset-db |
| `apps/backend/src/data-source.ts` | Standalone DataSource для TypeORM CLI (synchronize:false, migrationsRun:false) |
| `apps/backend/src/migrations/` | Папка миграций (`1740613433000-InitSchema.ts`, `1787755508525-AddFileEntity.ts`) |
| `apps/backend/src/database/reset-db.ts` | Dev-утилита: db:reset (drop + synchronize) |
| `apps/backend/src/database/recreate-db.ts` | Prod-prep: db:recreate (drop + накат миграций с нуля) |
| `apps/backend/src/users/entities/user.entity.ts` | User entity |
| `apps/backend/src/files/entities/file.entity.ts` | File entity |

## Сущности

### User

Таблица `user` — авторизация и управление пользователями.

| Column | Type | Constraints |
|--------|------|-------------|
| id | int (PK, auto) | — |
| login | string | unique, not null |
| passwordHash | string | not null |
| role | varchar | default 'user', values: 'admin', 'user' |
| createdAt | datetime | — |
| updatedAt | datetime | — |

### File

Таблица `file` — метаданные файлов в S3. Создаётся при прямой загрузке (`inStorage=true`) и при запросе presigned-upload (`inStorage=false`, подтверждается через `update-meta`).

| Column | Type | Constraints |
|--------|------|-------------|
| id | int (PK, auto) | — |
| fileKey | varchar(512) | unique, not null |
| originalName | varchar | nullable |
| size | varchar | nullable (строка — байты) |
| contentType | varchar | nullable |
| inStorage | boolean | default false |
| userId | integer | nullable |
| createdAt | datetime | — |
| updatedAt | datetime | — |

## Режимы БД

| Режим | `DB_SYNCHRONIZE` | Поведение |
|-------|-------------------|----------|
| Dev | `true` (default) | `synchronize: true`, миграции не запускаются |
| Prod | `false` | `synchronize: false`, `migrationsRun: true` — pending миграции накатываются при старте |

Подробнее — см. [docs/migrations.md](../migrations.md).

## Автосоздание БД (postgres)

`ensureDatabaseExists()` из `ensure-database.ts` вызывается в `main.ts` до инициализации Nest. Только для `DB_TYPE=postgres`:

- Подключается к системной maintenance-базе `postgres` (создаётся initdb всегда) — с ретраями: 5 попыток × 3с (postgres может стартовать позже backend'а).
- Проверяет `SELECT 1 FROM pg_database WHERE datname = <DB_DATABASE>`; если БД нет — `CREATE DATABASE` (имя экранируется кавычками).
- После этого TypeORM (`migrationsRun`) накатывает таблицы сам.

**Зачем**: `POSTGRES_DB` в контейнере postgres применяется только при первой инициализации тома; если том уже создан с другим именем БД (переименование проекта, старый деплой, ручные эксперименты), backend раньше падал с `FATAL: database "X" does not exist`. Теперь это самовосстанавливается при старте.

**Требование**: `DB_USERNAME` должен иметь право `CREATEDB` (в шаблоне `POSTGRES_USER` создаётся образом postgres как superuser — права есть). Для `DB_TYPE=sqlite` — no-op.

## Seeding

При `OnModuleInit` в `AppModule`: если в таблице `user` нет записей — создаётся первый админ (role='admin') из `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars.

## Утилиты БД

```bash
npm run db:reset      # Dev: drop all tables + recreate via synchronize
npm run db:recreate   # Prod-prep: drop + накат миграций с нуля (отказывает на дефолтном dev-SQLite)
npm run migration:run  # Накатить pending-миграции (через TypeORM CLI)
npm run migration:revert  # Откатить последнюю миграцию
```

## Common issues

1. **SQLite vs PostgreSQL types**: date columns serialized differently
2. **DB not ready at startup**: TypeORM `synchronize` may take a moment, check `logs/backend.log`. Для postgres backend сам ретраит подключение (5×3с) и создаёт БД, если её нет (см. «Автосоздание БД»); требуется `DB_USERNAME` с правом `CREATEDB`
3. **Миграции не найдены в prod**: убедитесь, что `nest build` компилирует `src/migrations/` → `dist/migrations/` (tsconfig `include: ["src/**/*"]`)