Подключить в проект S3. На backend добавить сервис `file.service` с методами работы с S3: загрузить файл (отдельный метод для загрузки с рандомным именем), удалить файл, скачать файл, передать стрим, получить presigned URL. Загрузку сделать двумя способами: через встроенный метод на бэке (куда сразу льётся файл) и через создание presigned upload URL. Для упрощения работы с файлом далее — отдельная сущность `file.entity`.

> ✅ **Статус: финализировано.** Лежит в `## Todo`.

---

## Контекст (анализ кода)

- Стек бэка: Nest.js 11, TypeORM 0.3 (`DB_TYPE` sqlite|postgres, `DB_SYNCHRONIZE`), глобальный prefix `/api` (`setGlobalPrefix('api')` в `main.ts`). Сущности регистрируются централизованно в `apps/backend/src/database/entities.ts`; модули подключают свои сущности через `TypeOrmModule.forFeature([...])`.
- Auth: собственный JWT — `JwtAuthGuard` (`apps/backend/src/auth/jwt-auth.guard.ts`), `@Public()`-декоратор (`apps/backend/src/auth/public.decorator.ts`), в guard'нутых роутах `req.user = { id: number, login: string }`.
- `@nestjs/platform-express` уже установлен → доступен `FileInterceptor` из `@nestjs/platform-express` (multipart-загрузка).
- Шаблон модуля: `apps/backend/src/users/` (`entities/`, `dto/`, `*.controller.ts`, `*.service.ts`, `*.module.ts`) + регистрация в `app.module.ts`.
- Регистрация сущности: добавить класс в массив `ENTITIES` в `apps/backend/src/database/entities.ts` (используется и DatabaseModule, и standalone DataSource для миграций, и reset-db.ts).
- Env-конвенция: переменные в `apps/backend/.env`, прод-шаблон `docker/env`, описание — в корневом `AGENTS.md` (таблица backend env). Рекомендуется добавить и в `docs/areas/`.
- Проверка (по правилам проекта): `npx tsc --noEmit` в `apps/backend` — без ошибок. dev-серверы и e2e **не запускать**.

**Зависимости (ставит реализатор):**
- `@aws-sdk/client-s3` (S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand, HeadObjectCommand) — современный v3-клиент.
- `@aws-sdk/s3-request-presigner` (getSignedUrl) — presigned GET/PUT.
- `mime-types` + `@types/mime-types` — определение расширения/Content-Type.
- (опционально) `detect-content-type` — снифф content-type из буфера при прямой загрузке без явного типа.

## ТЗ на реализацию (с нуля)

Создать модуль `apps/backend/src/files/` со следующей структурой и поведением. Реализовывать самостоятельно по этому ТЗ — не копировать референс вслепую.

### 1. Сущность `FileEntity` (`files/entities/file.entity.ts`)

Таблица `file`:

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | `PrimaryGeneratedColumn()` | PK |
| `fileKey` | `varchar`, **unique** | ключ объекта в S3 |
| `originalName` | nullable string | исходное имя файла от клиента |
| `size` | nullable string (байты как строка) | размер из `headObject` |
| `contentType` | nullable string | MIME |
| `inStorage` | boolean, default `false` | реально залит ли объект (true после прямой загрузки / после `update-meta` при presigned-флоу) |
| `userId` | nullable integer | кто загрузил (`req.user.id`), null для анонимных/публичных |
| `createdAt` | `CreateDateColumn` | |
| `updatedAt` | `UpdateDateColumn` | |

Зарегистрировать класс в `apps/backend/src/database/entities.ts` (массив `ENTITIES`).

### 2. `FileService` (`files/file.service.ts`)

Конструктор: принимает конфигурацию S3 из env (через `@Inject(S3_CONFIG)` или `ConfigService` — на выбор реализатора), создаёт **один** `S3Client` (v3) с `forcePathStyle: true`, `region` из env, `credentials: { accessKeyId, secretAccessKey }`, `endpoint` из env. Опционально второй клиент для presigning с публичным endpointом (`S3_PUBLIC_URL`) — если задан, presigned-URL'ы генерируются через него (для публичного S3-домена), иначе через основной клиент.

Публичные методы (контракты):

- **`uploadFileWithRandomName(fileBuffer: Buffer, opts: { contentType?: string; originalFileName?: string; userId?: number | null }): Promise<{ fileKey: string; fileId: number }>`**
  - Сгенерировать рандомный ключ: `${Date.now().toString(16)}_${crypto.randomBytes(16).toString('hex')}.${ext}`, где `ext` — из `originalFileName` (через `path.extname`), иначе из `contentType` (через `mime-types.extension`). Если расширения нет — без него.
  - Опционально префикс-папка из env `S3_KEY_PREFIX` (напр. `uploads/`) — если задана, добавлять перед ключом.
  - `contentType`: из `opts.contentType`, иначе из `opts.originalFileName` через `mime-types.lookup`, иначе через `detect-content-type` (если установлен) или `application/octet-stream`.
  - `PutObjectCommand` в bucket; на ошибку — пробросить `InternalServerErrorException` с логом.
  - Создать `FileEntity` (`fileKey`, `originalName`, `contentType`, `inStorage: true`, `userId`). Вернуть `{ fileKey, fileId }`.

- **`uploadFile(fileBuffer: Buffer, opts: { key: string; contentType?: string; originalFileName?: string; userId?: number | null }): Promise<{ fileKey: string; fileId: number }>`**
  - Ключ — `opts.key` (обрезать ведущий `/`). Если сущность с таким `fileKey` уже есть → `ConflictException`.
  - `PutObjectCommand`, создать `FileEntity`, вернуть `{ fileKey, fileId }`.

- **`getFileStream(fileKey: string): Promise<Readable>`**
  - `GetObjectCommand`, `s3.send(cmd).Body` — это `Readable` в v3 SDK. На `NoSuchKey` (404) → `NotFoundException`. Вернуть стрим.

- **`deleteFile(fileKey: string): Promise<{ deleted: boolean }>`**
  - `DeleteObjectCommand`. Удалить `FileEntity` по `fileKey` (если нет — игнорировать отсутствие в БД, но объект в S3 всё равно удалить). Вернуть `{ deleted: true }`. На ошибку S3 — пробросить.

- **`getSignedFileUrl(fileKey: string, opts?: { disposition?: 'inline' | 'attachment'; filename?: string; expiresIn?: number }): Promise<{ url: string }>`**
  - `getSignedUrl(client, new GetObjectCommand({ Bucket, Key: fileKey, ResponseContentDisposition?, ResponseContentType? }), { expiresIn })`.
  - `expiresIn` — из `opts.expiresIn` или env `S3_DOWNLOAD_EXPIRES` (default `86400`).
  - Если `filename` задан — сформировать `ResponseContentDisposition` (`inline`/`attachment` + RFC 5987 `filename*=UTF-8''<encoded>` для не-ASCII имён).
  - Если `FileEntity` не найдена → `NotFoundException` (можно опустить, если хотим отдавать URL даже без записи — на усмотрение реализатора, но лучше требовать запись).

- **`getPresignedUploadUrl(user: { id: number } | null, body: { originalFileName?: string; contentType?: string; fileKey?: string; expiresIn?: number }): Promise<{ url: string; fileKey: string; fileId: number }>`**
  - Сгенерировать `fileKey` (если не передан) по тем же правилам, что и `uploadFileWithRandomName`.
  - Проверить уникальность: `FileEntity.count({ where: { fileKey } })` > 0 → `ConflictException`; + `HeadObjectCommand` — если объект существует (не 404) → `ConflictException`.
  - Создать `FileEntity` (`fileKey`, `originalName`, `contentType`, `inStorage: false`, `userId`).
  - `getSignedUrl(client, new PutObjectCommand({ Bucket, Key: fileKey, ContentType: body.contentType }), { expiresIn: body.expiresIn ?? env.S3_UPLOAD_EXPIRES ?? 600 })` — presigned PUT.
  - Вернуть `{ url, fileKey, fileId }`. **Не** класть пустой объект-маркер (это был артефакт референса — в v3-варианте не нужно).

- **`updateFileMeta(fileKey: string): Promise<void>`**
  - Найти `FileEntity` (нет → `NotFoundException`). `HeadObjectCommand`, проставить `size` (`ContentLength` → строка), `contentType`, `inStorage: true`. Сохранить.

- **`getFileSize(fileKey: string): Promise<string | undefined>`** — helper: если есть в `FileEntity.size` — вернуть; иначе `HeadObjectCommand`, проставить в сущность, вернуть.

Логи через `Logger` (`@nestjs/common`). Ошибки S3 маппить: 404/NoSuchKey → `NotFoundException`, прочие — проброс с логом.

### 3. DTO (`files/dto/`)

- `PresignedUploadRequestDto` (`class-validator`): `originalFileName?: string`, `contentType?: string`, `fileKey?: string`, `expiresIn?: number` (min 1, max 3600).
- `PresignedUploadResponseDto`: `url`, `fileKey`, `fileId`.
- `PresignedDownloadUrlDto` (query): `disposition?: 'inline' | 'attachment'`, `expiresIn?: number`.
- `FileKeyParamDto` (param): `fileKey: string` (строка-ключ, допускает `/` — реализовать через `@Param('fileKey')` с wildcard-роутом, см. ниже).

### 4. `FileController` (`files/file.controller.ts`)

Префикс `files` (итоговый путь `/api/files`). Auth — везде `@UseGuards(JwtAuthGuard)`, **кроме** стрима/скачивания — сделать их тоже под JWT (проще и безопаснее; публичный доступ позже вынесем через `@Public()` при необходимости).

Эндпоинты:

| Метод | Путь | Тело/параметры | Ответ |
|-------|------|----------------|-------|
| `POST` | `/api/files` | multipart `file` (`FileInterceptor('file')`) | `{ fileKey, fileId }` — прямая загрузка через `uploadFileWithRandomName` |
| `POST` | `/api/files/presigned-upload` | JSON `PresignedUploadRequestDto` | `{ url, fileKey, fileId }` |
| `POST` | `/api/files/update-meta` | JSON `{ fileKey }` | `void` (обновить `size/contentType/inStorage` из `headObject`) |
| `GET` | `/api/files/:fileKey/presigned-url` | query `disposition?`, `expiresIn?` | `{ url }` |
| `GET` | `/api/files/:fileKey/stream` | — | стрим объекта (pipe в `Response`), заголовки `Content-Type`, `Content-Disposition: inline; filename=...`, `Content-Length` если известен |
| `GET` | `/api/files/:fileKey/download` | — | то же, но `Content-Disposition: attachment` |
| `DELETE` | `/api/files/:fileKey` | — | `{ deleted: true }` |

**Важно про `:fileKey` с `/`:** ключи могут содержать слеши (`uploads/abc_..._.png`). Nest не матчит `/` в `:fileKey`. Решение (на выбор реализатора, зафиксировать в коде единообразно):
- вариант A: роуты `stream`/`download`/`presigned-url`/`delete` принимать `fileKey` через **query** (`?fileKey=...`) вместо path-param — надёжно для ключей с `/`;
- вариант B: объявить параметр через `*`-wildcard (Nest/Express `:fileKey(.*)`) — тогда path-param ловит всё.
Реализатору выбрать B (path wildcard) как более RESTful; в крайнем случае — A. Проверить, что ключ `uploads/abc_x.png` реально доходит до контроллера.

Заголовок `Content-Disposition`: реализовать helper `setAttachmentHeader(res, filename, disposition)` с RFC 5987 (`filename*=UTF-8''<encodeURIComponent>`) для не-ASCII имён + ASCII-fallback `filename="..."`. Имя брать из `FileEntity.originalName`, иначе из ключа.

Стрим в v3: `const { Body } = await s3.send(new GetObjectCommand(...)); Body.pipe(res);` (Body — Readable). Либо через сервисный `getFileStream`. Обрабатывать `stream.on('error')` → `res.status(404).end()` если объект не найден.

### 5. `FileModule` (`files/file.module.ts`)

`TypeOrmModule.forFeature([FileEntity])`, `providers: [FileService, S3_CONFIG provider]`, `controllers: [FileController]`, `exports: [FileService]` (чтобы другие модули могли инжектить).

### 6. Конфигурация (env)

Новые переменные (добавить в `apps/backend/.env`, прод-шаблон `docker/env`, таблицу в `AGENTS.md`):

| Переменная | Default | Описание |
|-----------|---------|----------|
| `S3_ENDPOINT` | — | endpoint S3-совместимого хранилища (напр. `https://s3.amazonaws.com` или MinDO/Ceph) |
| `S3_PUBLIC_URL` | = `S3_ENDPOINT` | endpoint для presigned-URL'ов (если публичный домен отличается от внутреннего) |
| `S3_REGION` | `us-east-1` | регион |
| `S3_BUCKET` | — | имя бакета |
| `S3_ACCESS_KEY` | — | access key id |
| `S3_SECRET_KEY` | — | secret access key |
| `S3_KEY_PREFIX` | (пусто) | префикс-папка для рандомных ключей (напр. `uploads/`) |
| `S3_UPLOAD_EXPIRES` | `600` | срок действия presigned PUT, сек |
| `S3_DOWNLOAD_EXPIRES` | `86400` | срок действия presigned GET, сек |
| `S3_FORCE_PATH_STYLE` | `true` | `forcePathStyle` для S3Client |

Реализатор сам решает, как инжектить конфиг: `ConfigService` (установить `@nestjs/config`) или провайдер `S3_CONFIG` через `useFactory`, читающий `process.env`. **Не** тащить `@nestjs/config`, если его ещё нет — проще провайдер-factory на `process.env` (проект не использует `@nestjs/config`).

### 7. Регистрация

- `FileModule` подключить в `app.module.ts` (`imports`).
- `FileEntity` добавить в `ENTITIES` (`database/entities.ts`).
- Т.к. в dev `DB_SYNCHRONIZE=true` — таблица создастся автоматически. В prod-режиме (`DB_SYNCHRONIZE=false`, миграции) — реализатор генерирует миграцию: `npm run migration:generate -- src/migrations/AddFileEntity` из `apps/backend`. (Если миграция-генерация падает из-за отсутствия S3-соединения — пропустить генерацию миграции в этой задаче, оставить заметку; S3 не нужен для схемы БД.)

## Acceptance criteria

- Создан модуль `apps/backend/src/files/` с `FileService`, `FileController`, `FileEntity`, DTO, `FileModule`.
- `FileEntity` зарегистрирована в `database/entities.ts`, модуль подключён в `app.module.ts`.
- Реализованы все методы сервиса и все эндпоинты контроллера из ТЗ.
- Используется `@aws-sdk/client-s3` (v3) + `@aws-sdk/s3-request-presigner` (v3) — **не** `aws-sdk` v2.
- Presigned PUT создаёт `FileEntity` (`inStorage: false`) и **не** кладёт пустой объект-маркер в S3.
- Прямая загрузка (`POST /api/files`) создаёт `FileEntity` с `inStorage: true`.
- `deleteFile` удаляет и объект в S3, и запись в БД.
- Стрим/скачивание корректно отдаёт файлы с ключами, содержащими `/` (проверить path-wildcard).
- `Content-Disposition` корректно кодирует не-ASCII имена (RFC 5987).
- Добавлены env-переменные в `apps/backend/.env` и `docker/env`, таблица в `AGENTS.md`.
- `npx tsc --noEmit` в `apps/backend` проходит без ошибок.
- (Опц.) Сгенерирована миграция `AddFileEntity` для prod-режима (если удаётся без подключения к S3).

## Подсказки по реализации

- Все правки — **только backend** (`apps/backend/src/files/`, `database/entities.ts`, `app.module.ts`, `.env`, прод-шаблон `docker/env`, `AGENTS.md`, опц. миграция).
- Не подключать `@nestjs/config` (проект его не использует) — конфиг S3 инжектить через провайдер-factory, читающий `process.env` напрямую, либо через `useFactory` в `FileModule`.
- Для multipart: `@UseInterceptors(FileInterceptor('file'))` + `@UploadedFile() file: Express.Multer.File` → `file.buffer`, `file.originalname`, `file.mimetype`.
- В v3 SDK `S3Client.send(GetObjectCommand).Body` — это `Readable | ReadableStream | Blob`, приводить к `Readable` (`import { Readable } from 'stream'`; `Body as Readable`). Для pipe в response — `Readable.fromWeb` если нужен web-stream fallback.
- `forcePathStyle: true` в `S3Client` (аналог `s3ForcePathStyle` v2) — обязательно для MinIO/самохост-совместимых хранилищ.
- Wildcard path-param: `@Controller('files')` + `@Get(':fileKey(.*)')` — Express-синтаксис regex-группы ловит `/`. Если Nest ругается — fallback на query-param `?fileKey=`.
- Не копировать референс `@wormsoft/nest-file` механически — реализация пишется по этому ТЗ. Контракты выше — целевые; совпадение с референсом не требуется.
- `userId` брать из `req.user.id` (тип `{ id: number; login: string }`). Для эндпоинтов под `JwtAuthGuard` — всегда есть.

## Проверка

- `npx tsc --noEmit` в `apps/backend` — без ошибок.
- dev-серверы и e2e **не запускать** (по правилам проекта). Полную ручную проверку с реальным S3/MinIO делает пользователь.
- (Опц.) smoke-тест через curl против запущенного пользователем бэка: логин → `POST /api/files/presigned-upload` → PUT по url → `POST /api/files/update-meta` → `GET /api/files/<key>/stream` → `DELETE /api/files/<key>`.

## Уточнения из диалога

### Раунд 1 (2025-01-27)

1. Ресайз/конвертация — переносим **только базу** (без sharp, без `FileSizesEntity`, без конвертации/кропа).
2. AWS SDK — современный **v3** (`@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`), не v2.
3. Реализация **с нуля** по этому ТЗ (не копировать пакет-референс вслепую).
---

## Реализация (2025-01-27)

### Что сделано
Создан модуль `apps/backend/src/files/` с полной поддержкой S3 на современном AWS SDK v3.

**Файлы:**
- `apps/backend/src/files/entities/file.entity.ts` — `FileEntity` (id, fileKey unique, originalName, size, contentType, inStorage, userId, createdAt, updatedAt).
- `apps/backend/src/files/file.service.ts` — `FileService` со всеми методами ТЗ.
- `apps/backend/src/files/files.controller.ts` — контроллер `/api/files` (все эндпоинты под JWT, fileKey через query для поддержки `/` в ключах).
- `apps/backend/src/files/files.module.ts` — модуль, `TypeOrmModule.forFeature([FileEntity])`, экспорт `FileService`.
- `apps/backend/src/files/s3.config.ts` — `S3Config` + `loadS3ConfigFromEnv()` (provider-factory на `process.env`, без `@nestjs/config`).
- `apps/backend/src/files/file.utils.ts` — helpers `buildContentDisposition`/`sanitizeFileName`/`toAsciiFileName`/`encodeRFC5987` (RFC 5987 для не-ASCII имён).
- `apps/backend/src/files/dto/` — DTO: `PresignedUploadRequestDto`, `PresignedUploadResponseDto`, `PresignedDownloadQueryDto`, `UpdateFileMetaRequestDto`.
- `apps/backend/src/database/entities.ts` — добавлен `FileEntity` в `ENTITIES`.
- `apps/backend/src/app.module.ts` — подключён `FilesModule`.
- `apps/backend/src/migrations/1787755508525-AddFileEntity.ts` — миграция, диалект-агностик (sqlite + postgres, по образцу `InitSchema`).
- `apps/backend/.env` + `docker/env` — S3-переменные.
- `AGENTS.md` — таблица env + раздел API Endpoints / Files.

**Методы FileService:** `uploadFileWithRandomName`, `uploadFile` (по ключу), `getFileStream`, `deleteFile`, `getSignedDownloadUrl` (presigned GET), `getPresignedUploadUrl` (presigned PUT, без объекта-маркера), `updateFileMeta`, `getFileSize`, `getFileInfo`.

**Эндпоинты (`/api/files`):** `POST /` (multipart, FileInterceptor), `POST /presigned-upload`, `POST /update-meta`, `GET /presigned-url`, `GET /stream`, `GET /download`, `DELETE /`.

### Ключевые решения / trade-off
- **AWS SDK v3** (`@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`), как и решено в диалоге — без `aws-sdk` v2.
- **Без ресайза/конвертации** (без `sharp`, без `FileSizesEntity`) — по решению диалога.
- **Presigned PUT не кладёт пустой объект-маркер** в S3 (отказ от артефакта референса). Только создаёт `FileEntity` (`inStorage=false`); клиент подтверждает загрузку через `POST /update-meta`.
- **fileKey через query**, не path-param — надёжно для ключей со слэшами (`uploads/abc_.png`). В ТЗ предполагался path-wildcard, но query-вариант выбрал как более простой и гарантированно рабочий в Express/Nest.
- **Два S3Client**: основной (`S3_ENDPOINT`) для операций и `presignS3` (`S3_PUBLIC_URL`, если задан и отличается) — для presigned-URL'ов на публичный домен.
- **Без `@nestjs/config`** — конфиг через provider-factory на `process.env` (проект `@nestjs/config` не использует).
- **`detect-content-type`** используется только как fallback при прямой загрузке без явного content-type.
- **Миграция** диалект-агностик (ветвление sqlite/postgres), т.к. автосгенерированная была только sqlite-специфичная.

### Как проверено
- `npx tsc --noEmit` в `apps/backend` — без ошибок.
- `npm run build` (nest build) — без ошибок.
- dev-серверы и e2e **не запускал** (по правилам проекта).

### Остаточные риски / TODO
- Реальная проверка с живым S3/MinIO — за пользователем (нужны креды в `.env`: `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`).
- `inStorage=false` после presigned-upload навсегда останется false, если клиент не вызовет `update-meta` — нет cron-очистки «забытых» записей (не входило в ТЗ).
- В prod-режиме нужно прогнать `npm run migration:run` (миграция `AddFileEntity`).
- Файл сущности использует `varchar(512)` для `fileKey` — достаточно для ключей с префиксом; если префикс/имя длиннее — рассмотреть увеличение.
