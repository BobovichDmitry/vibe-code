Убрать текущий бизнес-функционал (уведомления/reminders + telegram-настройки) и оставить голый каркас приложения: аутентификация, управление пользователями, публичная страница со счётчиком пользователей. Дальше пользователь сам разрабатывает механики поверх каркаса.

> **Решения по вопросам:** Q6 — каркас как рекомендовано: auth + users + публичный `GET /api/users/count` + `PublicView.vue` + e2e `basic.spec.ts` остаются; CLI `create-admin` остаётся. Удаляются только модули `reminders` и `settings` (telegram).

---

## Контекст (анализ кода)

Бизнес-функционал в проекте сейчас:

- **Backend `apps/backend/src/reminders/`** — модуль напоминаний: `entities/reminder.entity.ts`, `reminders.controller.ts` (`/api/reminders` CRUD, per-user), `reminders.service.ts`, `reminders.module.ts`, `dto/`. Зарегистрирован в `app.module.ts` (`RemindersModule`).
- **Backend `apps/backend/src/settings/`** — модуль настроек telegram-бота: `entities/settings.entity.ts`, `settings.controller.ts` (`GET/PATCH /api/settings`, `POST /api/settings/send-test`), `settings.service.ts`, `settings.module.ts`, `dto/`. Зарегистрирован в `app.module.ts` (`SettingsModule`). Сущность сидируется автоматически (telegram bot token и т.д.).
- **Frontend `apps/frontend/src/views/RemindersView.vue`** — весь UI напоминаний.
- **Frontend `apps/frontend/src/views/admin/TelegramBotView.vue`** — админ-страница telegram-бота.
- **Frontend `apps/frontend/src/api/reminders.ts`, `apps/frontend/src/api/settings.ts`** — axios-клиенты.
- **Роут `apps/frontend/src/router/index.ts`**: маршрут `/reminders` (requires auth) и дочерний `/admin/telegram-bot`.
- **E2E `e2e/tests/telegram-settings.spec.ts`** — тест telegram-настройки (упадёт после удаления).
- **Docs**: `docs/areas/reminders.md`, `docs/areas/admin-panel.md` (упоминание telegram), `docs/areas/backend-api-structure.md`, `docs/areas/frontend-structure.md`, `docs/areas/database-structure.md` — описывают reminders/settings.

Каркас, который ОСТАЁТСЯ:
- `apps/backend/src/auth/` — JWT-логин/`me`/смена пароля, сущность `AdminEntity`/`UserEntity` с ролями `admin`/`user`.
- `apps/backend/src/users/` — CRUD пользователей (admin only), публичный `GET /api/users/count`.
- `apps/backend/src/database/` — TypeORM-конфиг (но `ENTITIES` сейчас включает `ReminderEntity` и `SettingsEntity` — убрать).
- `apps/backend/src/main.ts`, `app.module.ts` (сид первого админа на пустой БД — оставить).
- Frontend: `LoginView.vue`, `PublicView.vue` (счётчик), `admin/ManageUsersView.vue`, `AdminLayout.vue`, `api/auth.ts`, `api/users.ts`, `composables/useAuth.ts`, `useTheme.ts`.

## Acceptance criteria

- [ ] Удалены backend-модули `reminders/` и `settings/` целиком (папки + регистрации из `app.module.ts`).
- [ ] `apps/backend/src/database/database.module.ts`: `ENTITIES` содержит только `UserEntity` (и `AdminEntity`, если он отдельный — проверить). Убран импорт `ReminderEntity`/`SettingsEntity`. Авто-seed настроек telegram удалён (сид первого админа в `AppModule.onModuleInit` остаётся).
- [ ] `apps/backend/src/cli/` — проверить `create-admin.ts` (если ссылается на settings/reminders — почистить); оставить рабочим.
- [ ] Удалены frontend: `RemindersView.vue`, `admin/TelegramBotView.vue`, `api/reminders.ts`, `api/settings.ts`.
- [ ] `apps/frontend/src/router/index.ts`: убран роут `/reminders` и дочерний `/admin/telegram-bot`. `/admin` redirect на users — остаётся. Маршрут `/reminders` больше нигде не referenced (проверить `rg '/reminders'`).
- [ ] `AdminLayout.vue`: `navItems` содержит только «Пользователи» (telegram-пункт убран). Логику темы/выхода — не трогать (рестайл — отдельная задача 04).
- [ ] `PublicView.vue` — оставить как есть (счётчик пользователей).
- [ ] Удалён e2e-тест `e2e/tests/telegram-settings.spec.ts`. `e2e/tests/basic.spec.ts` — проверить, не ссылается ли на reminders/telegram; если ссылается — убрать эти шаги (логин + users + count должны остаться зелёными).
- [ ] `docs/`: удалён `docs/areas/reminders.md`; обновлены `docs/areas/admin-panel.md`, `docs/areas/backend-api-structure.md`, `docs/areas/frontend-structure.md`, `docs/areas/database-structure.md`, `docs/areas/auth-structure.md` (убрать упоминания reminders/settings/telegram); обновлён `docs/context-index.md` (ссылка на reminders.md убрана); `docs/deployment.md`/`GETTING_STARTED.md` — убрать упоминание telegram-настроек, если есть. Эту часть лучше делегировать `@docs-maintainer`.
- [ ] Корневой `AGENTS.md`: убрать из таблицы API-эндпоинтов reminders + settings, из карты модулей — `reminders/`/`settings/`, убрать упоминание «Telegram bot settings» в Settings и env `ADMIN_PASSWORD` и т.п. — оставить только относящееся к каркасу.
- [ ] `package.json` (root и `apps/backend`): убрать скрипты, ссылающиеся на удалённое (если такие есть — `db:reset` остаётся, `create-admin` остаётся).
- [ ] Нет осиротевших импортов: `rg -i "reminder|settings|telegram" apps/ --type ts --type vue` после удаления возвращает только легитимные (например `useTheme`/`useAuth`/`useBranding` — последнее если появится позже в задаче 04).
- [ ] Backend собирается: `cd apps/backend && npx tsc --noEmit` — чисто.
- [ ] Frontend собирается: `cd apps/frontend && npx vue-tsc --noEmit` — чисто.

## Подсказки по реализации

- Порядок: сначала backend (модули + `app.module.ts` + `database.module.ts` + `cli`), потом frontend (views/api/router/layout), потом e2e, потом docs/AGENTS.
- `AdminEntity` и `UserEntity` — проверить, одна ли это сущность или две. В `database.module.ts` сейчас `ENTITIES = [UserEntity, SettingsEntity, ReminderEntity]`. Если `AdminEntity` отдельный — оставить.
- После удаления модулей сид админа в `AppModule.seedAdmin()` использует `UsersService.create({ login, password, role: 'admin' })` — должно работать без reminders/settings.
- В e2e `basic.spec.ts` нет напоминаний (только login → create user → count) — скорее всего трогать не нужно, но проверить `rg -i "reminder|telegram" e2e/`.
- Не запускать dev-серверы/e2e. Проверка — только типы.

## Проверка

- `cd apps/backend && npx tsc --noEmit` — без ошибок.
- `cd apps/frontend && npx vue-tsc --noEmit` — без ошибок.
- `rg -i "reminder|telegram|settings" apps/backend/src apps/frontend/src` — пусто (кроме `useTheme`/`system` и легитимного).
- `git status` — удалены файлы reminders/settings; изменены `app.module.ts`, `database.module.ts`, router, `AdminLayout.vue`, docs, `AGENTS.md`.