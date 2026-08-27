# Backend API Structure

## Описание

Nest.js API с глобальным префиксом `/api`. Модули: `AuthModule` (JWT авторизация), `UsersModule` (CRUD пользователей), `FilesModule` (загрузка/хранение файлов в S3), `BrandingModule` (брендинг). База данных: SQLite (dev) / PostgreSQL (prod) через TypeORM.

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/backend/src/main.ts` | Entry point: bootstrap, cookie-parser, CORS, global prefix 'api', порт 3001 (чистый API, статика не раздаётся) |
| `apps/backend/src/env.ts` | Загрузчик env: `.env` → `.env.local` (override), внешнее окружение — наивысший приоритет |
| `apps/backend/src/app.module.ts` | Root module: DatabaseModule, AuthModule, UsersModule, BrandingModule, FilesModule |
| `apps/backend/src/auth/` | JWT auth module |
| `apps/backend/src/users/` | User CRUD module |
| `apps/backend/src/files/` | Files module (S3-хранилище, presigned-URL, прямая загрузка) |
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

### Files

Все эндпоинты под JWT. `fileKey` передаётся через query (`?fileKey=...`) для поддержки ключей со слэшами (напр. `uploads/abc_.png`). Прямая загрузка — multipart-поле `file`.

| Method | Endpoint | Auth | Описание |
|--------|----------|------|----------|
| GET | `/api/files` | JWT | Список файлов (фильтр `search` по fileKey — подстрока, пагинация `limit`/`offset`) → `{ items, total }` |
| POST | `/api/files` | JWT | Прямая загрузка (multipart `file`, рандомное имя) → `{ fileKey, fileId }` (`inStorage=true`) |
| POST | `/api/files/presigned-upload` | JWT | Presigned PUT-URL (создаёт `FileEntity`, `inStorage=false`) → `{ url, fileKey, fileId }` |
| POST | `/api/files/update-meta` | JWT | Подтянуть size/contentType из `headObject`, поставить `inStorage=true` |
| GET | `/api/files/presigned-url?fileKey=&disposition=&expiresIn=&filename=` | JWT | Presigned GET-URL → `{ url }` |
| GET | `/api/files/stream?fileKey=` | JWT | Стрим файла (`inline` Content-Disposition) |
| GET | `/api/files/download?fileKey=` | JWT | Скачивание (`attachment` Content-Disposition) |
| DELETE | `/api/files?fileKey=` | JWT | Удалить объект в S3 + запись в БД |

**List query**: `search?`, `limit?` (1..200), `offset?` (≥0)
**Presigned-upload request**: `{ originalFileName?, contentType?, fileKey?, expiresIn? (1..3600) }`
**Presigned-download query**: `fileKey`, `disposition?` (`inline`|`attachment`), `expiresIn?`, `filename?`

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

### FilesModule

- `file.service.ts` — `uploadFileWithRandomName()`, `uploadFile()`, `getFileStream()`, `deleteFile()`, `getSignedDownloadUrl()` (presigned GET), `getPresignedUploadUrl()` (presigned PUT без объекта-маркера), `updateFileMeta()`, `getFileSize()`, `getFileInfo()`, `listFiles()`
- `files.controller.ts` — все эндпоинты `/api/files/*` (JWT)
- `entities/file.entity.ts` — таблица `file` (fileKey unique, originalName, size, contentType, inStorage, userId, createdAt, updatedAt)
- `s3.config.ts` — `loadS3ConfigFromEnv()` (читает `S3_*` env, `useFactory` в модуле)
- `file.utils.ts` — `buildContentDisposition()` (RFC 5987 кодирование имён)
- `dto/` — `ListFilesQueryDto`, `PresignedUploadRequestDto`, `PresignedDownloadQueryDto`, `UpdateFileMetaRequestDto`
- AWS SDK v3 (`@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`), без sharp/ресайза

## Auth Guard

Все user endpoints защищены `@UseGuards(JwtAuthGuard)`. Guard извлекает user из JWT payload (`sub` = user.id). Публичные маршруты помечены `@Public()`.

## Seeding

При старте (OnModuleInit): если нет пользователей в БД — создаётся первый админ (role='admin') из `ADMIN_LOGIN` / `ADMIN_PASSWORD` env vars.

## Database

- TypeORM `synchronize: true` (auto-migrate, dev) / миграции (prod)
- SQLite for dev: `DB_TYPE=sqlite`, `DB_SQLITE_PATH=./data/database.sqlite`
- PostgreSQL for prod: `DB_TYPE=postgres`, `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE`

**Сущности** (общий список `ENTITIES` в `database/entities.ts`):
- `user` — пользователи (login, passwordHash, role, createdAt, updatedAt)
- `file` — метаданные файлов в S3 (fileKey unique, originalName, size, contentType, inStorage, userId, createdAt, updatedAt)

## Env / .env.local

Базовый `.env` под версионным контролем. `.env.local` (не под git) переопределяет `.env` (`override: true`) — сюда кладут локальные креды S3/MinIO. Шаблон: `apps/backend/.env.local.example`. Внешнее окружение (прод-контейнер, systemd) имеет наивысший приоритет — dotenv его не перезаписывает. Загрузчик: `apps/backend/src/env.ts` (заменил `import 'dotenv/config'` во всех точках входа).

S3-переменные: `S3_ENDPOINT`, `S3_PUBLIC_URL`, `S3_REGION`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_KEY_PREFIX`, `S3_UPLOAD_EXPIRES` (600), `S3_DOWNLOAD_EXPIRES` (86400), `S3_FORCE_PATH_STYLE` (true). Полный список — в корневом `AGENTS.md`.

## Common issues

1. **`EADDRINUSE` on port 3000**: `npm run kill:backend`
2. **JWT expired**: token expires in 24h, re-login
3. **CORS blocked**: set `CORS_ORIGIN` in backend `.env`
4. **DB not ready**: wait for TypeORM connection (check `logs/backend.log`)