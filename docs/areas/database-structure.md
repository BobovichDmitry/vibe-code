# Database Structure

## Описание

TypeORM с двумя подключениями: SQLite (dev) / PostgreSQL (prod). `synchronize: true` для auto-migration. Одна сущность: User (авторизация и управление пользователями).

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/database/database.module.ts` | TypeORM config (SQLite/PostgreSQL via DB_TYPE env) |
| `apps/backend/src/database/reset-db.ts` | DB reset script (drop + recreate) |
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

## Seeding

При `OnModuleInit` в `AppModule`: если в таблице `user` нет записей — создаётся первый админ (role='admin') из `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars.

## Reset DB

```bash
npm run db:reset
```

Drop all tables + recreate.

## Common issues

1. **SQLite vs PostgreSQL types**: date columns serialized differently
2. **DB not ready at startup**: TypeORM `synchronize` may take a moment, check `logs/backend.log`