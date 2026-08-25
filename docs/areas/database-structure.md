# Database Structure

## Описание

TypeORM с двумя подключениями: SQLite (dev) / PostgreSQL (prod). Два режима работы:
- **Dev**: `DB_SYNCHRONIZE=true` → `synchronize: true` (быстрая итерация, миграции не запускаются).
- **Prod**: `DB_SYNCHRONIZE=false` → `synchronize: false`, `migrationsRun: true` (pending-миграции накатываются при старте Nest).

Одна сущность: User (авторизация и управление пользователями).

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/database/database.module.ts` | TypeORM config (SQLite/PostgreSQL via DB_TYPE, режимы via DB_SYNCHRONIZE) |
| `apps/backend/src/database/entities.ts` | Единый `ENTITIES` — общий для Nest-модуля, DataSource и reset-db |
| `apps/backend/src/data-source.ts` | Standalone DataSource для TypeORM CLI (synchronize:false, migrationsRun:false) |
| `apps/backend/src/migrations/` | Папка миграций (baseline `1740613433000-InitSchema.ts`) |
| `apps/backend/src/database/reset-db.ts` | Dev-утилита: db:reset (drop + synchronize) |
| `apps/backend/src/database/recreate-db.ts` | Prod-prep: db:recreate (drop + накат миграций с нуля) |
| `apps/backend/src/users/entities/user.entity.ts` | User entity |

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

## Режимы БД

| Режим | `DB_SYNCHRONIZE` | Поведение |
|-------|-------------------|----------|
| Dev | `true` (default) | `synchronize: true`, миграции не запускаются |
| Prod | `false` | `synchronize: false`, `migrationsRun: true` — pending миграции накатываются при старте |

Подробнее — см. [docs/migrations.md](../migrations.md).

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
2. **DB not ready at startup**: TypeORM `synchronize` may take a moment, check `logs/backend.log`
3. **Миграции не найдены в prod**: убедитесь, что `nest build` компилирует `src/migrations/` → `dist/migrations/` (tsconfig `include: ["src/**/*"]`)