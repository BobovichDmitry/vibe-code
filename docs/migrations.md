# Миграции БД — двухрежимная работа

## Режимы

| Режим | `DB_SYNCHRONIZE` | Поведение | Применение |
|-------|-------------------|----------|------------|
| Dev | `true` (default) | `synchronize: true`, миграции НЕ запускаются | Локальная разработка, e2e |
| Prod | `false` | `synchronize: false`, `migrationsRun: true` — pending-миграции накатываются при старте Nest | Production, Docker |

Переключение — одной env-переменной `DB_SYNCHRONIZE`.

## Файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/database/database.module.ts` | Nest.js TypeORM config (synchronize / migrationsRun по `DB_SYNCHRONIZE`) |
| `apps/backend/src/database/entities.ts` | Единый `ENTITIES` — общий для Nest-модуля, DataSource и reset-db |
| `apps/backend/src/data-source.ts` | Standalone DataSource для TypeORM CLI (`synchronize:false`, `migrationsRun:false`) |
| `apps/backend/src/migrations/` | Папка миграций (glob `*.{ts,js}`) |
| `apps/backend/src/database/reset-db.ts` | `db:reset` — dev-утилита (drop + synchronize) |
| `apps/backend/src/database/recreate-db.ts` | `db:recreate` — prod-prep (drop + накат миграций с нуля) |

## npm-скрипты

### Backend (`apps/backend/package.json`)

| Скрипт | Команда | Описание |
|--------|---------|----------|
| `typeorm` | `typeorm-ts-node-commonjs` | TypeORM CLI через ts-node |
| `migration:generate` | `migration:generate -d src/data-source.ts` | Сгенерировать миграцию из diff сущностей |
| `migration:create` | `migration:create src/migrations/` | Создать пустую миграцию |
| `migration:run` | `migration:run -d src/data-source.ts` | Накатить pending-миграции |
| `migration:revert` | `migration:revert -d src/data-source.ts` | Откатить последнюю миграцию |
| `db:reset` | `ts-node src/database/reset-db.ts` | Dev: drop + synchronize |
| `db:recreate` | `ts-node src/database/recreate-db.ts` | Prod-prep: drop + накат миграций |

### Root (`package.json`)

Зеркальные скрипты через `--workspace=apps/backend`:

```bash
npm run migration:generate -- src/migrations/MyMigration
npm run migration:run
npm run migration:revert
npm run db:recreate
```

## Prod-prep цикл проверки дрейфа

Чтобы убедиться, что миграции описывают схему полностью:

```bash
# 1. Пересоздать БД с нуля через миграции
DB_TYPE=postgres DB_HOST=... npm run db:recreate

# 2. Сгенерировать diff — должно быть "No changes"
npm run migration:generate -- src/migrations/_check

# 3. Если "No changes" — удалить _check
#    Если есть изменения — добавить их в реальную миграцию
```

## Как добавить изменение схемы

1. Изменить сущность в `apps/backend/src/users/entities/` (или новую в `entities.ts`).
2. Сгенерировать миграцию:
   ```bash
   npm run migration:generate -- src/migrations/AddNewColumn
   ```
3. Проверить сгенерированный код (диалект-агностик, Table API).
4. На dev (`DB_SYNCHRONIZE=true`) — изменения применятся через synchronize автоматически.
5. На prod (`DB_SYNCHRONIZE=false`) — миграция накатится при старте Nest.

## Docker / Production

- `docker/env` / `docker/.env.example`: `DB_SYNCHRONIZE=false`.
- `nest build` компилирует `src/migrations/` → `dist/migrations/` (tsconfig `include: ["src/**/*"]`).
- `database.module.ts` резолвит миграции через `join(__dirname, '..', 'migrations', '*.{ts,js}')` — работает и в dev (`src/migrations/*.ts`), и в prod (`dist/migrations/*.js`).
- При старте Nest в prod-режиме pending-миграции накатываются автоматически (`migrationsRun: true`).

## Baseline-миграция

`1740613433000-InitSchema.ts` — создаёт всю схему каркаса одной миграцией:

- Таблица `user` (id, login, passwordHash, role, createdAt, updatedAt)

Диалект-агностик — Table API (без голого SQL-ветвления). Для boolean-default в будущем: `type === 'sqlite'` → `0` / `false` для postgres.