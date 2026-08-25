# Backend API Structure

## Описание

Nest.js API с глобальным префиксом `/api`. Два модуля: `AuthModule` (JWT авторизация) и `UsersModule` (CRUD пользователей). База данных: SQLite (dev) / PostgreSQL (prod) через TypeORM.

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/main.ts` | Entry point: bootstrap, CORS, global prefix 'api', SPA fallback |
| `apps/backend/src/app.module.ts` | Root module: imports AuthModule, UsersModule, DatabaseModule |
| `apps/backend/src/auth/` | JWT auth module |
| `apps/backend/src/users/` | User CRUD module |
| `apps/backend/src/database/database.module.ts` | TypeORM config (SQLite/PostgreSQL) |

## API Endpoints

### Auth

| Method | Endpoint | Auth | Описание |
|--------|----------|------|----------|
| POST | `/api/auth/login` | — | Login → `{ access_token }` |
| GET | `/api/auth/me` | JWT | Current user info |
| PATCH | `/api/auth/password` | JWT | Change password |

**Login request**: `{ login: string, password: string }`
**Login response**: `{ access_token: string }` (expires in 24h)

### Users

| Method | Endpoint | Auth | Описание |
|--------|----------|------|----------|
| GET | `/api/users/count` | — | User count (public) |
| GET | `/api/users` | JWT | All users |
| GET | `/api/users/:id` | JWT | Single user |
| POST | `/api/users` | JWT | Create user |
| PATCH | `/api/users/:id` | JWT | Update user |
| DELETE | `/api/users/:id` | JWT | Delete user |

**Create user request**: `{ login: string, password: string, role?: 'admin' | 'user' }`
**User response**: `{ id, login, role, createdAt, updatedAt }` (no passwordHash)

## Структура модулей

### AuthModule

- `auth.service.ts` — `validateLogin()`, `validateJwtPayload()`, `changePassword()`
- `auth.controller.ts` — `/login`, `/me`, `/password`
- `jwt.strategy.ts` — Passport JWT strategy (reads `sub` from token)
- `jwt-auth.guard.ts` — Guard for protected routes, respects `@Public()`
- `public.decorator.ts` — `@Public()` decorator to skip auth guard

### UsersModule

- `users.service.ts` — `findAll()`, `findOne()`, `create()`, `update()`, `remove()`, `count()`, `changePassword()`
- `users.controller.ts` — CRUD endpoints + `GET /users/count` (public)
- `entities/user.entity.ts` — User table (login, passwordHash, role, createdAt, updatedAt)

## Auth Guard

Все user endpoints защищены `@UseGuards(JwtAuthGuard)`. Guard извлекает user из JWT payload (`sub` = user.id). Публичные маршруты помечены `@Public()`.

## Seeding

При старте (OnModuleInit): если нет пользователей в БД — создаётся первый админ (role='admin') из `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars.

## Database

- TypeORM `synchronize: true` (auto-migrate)
- SQLite for dev: `DB_TYPE=sqlite`, `DB_SQLITE_PATH=./data/database.sqlite`
- PostgreSQL for prod: `DB_TYPE=postgres`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`

**Сущности:**
- `user` — пользователи (login, passwordHash, role, createdAt, updatedAt)

## Common issues

1. **`EADDRINUSE` on port 3000**: `npm run kill:backend`
2. **JWT expired**: token expires in 24h, re-login
3. **CORS blocked**: set `CORS_ORIGIN` in backend `.env`
4. **DB not ready**: wait for TypeORM connection (check `logs/backend.log`)