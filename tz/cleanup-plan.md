# План: трансформация Meeting UI в шаблон с админ-панелью пользователей

## Цель

Превратить существующее приложение «календарь для встреч» в **универсальный стартовый шаблон** для агентской разработки, включающий:

- админ-панель с управлением пользователями (роли admin/user)
- публичную часть с отображением текущей статистики
- базовый e2e тест (вход → создание пользователя → проверка статистики)
- файлы деплоя
- документацию (запуск с нуля, работа с агентами)
- `agents.md` с правилами разработки

---

## Агенты и границы ответственности

### 1. 🧩 `cleanup-backend` — Backend: упрощение + пользователи

**Ответственность**: Убрать бизнес-логику календаря, добавить CRUD пользователей с ролями.

**Задачи**:
- Удалить из `events/` все сущности и логику: bookings, free-slots, schedules, vacations, slot-exclusions, settings, notifications, ics-sources
- Удалить модули `notifications/` и `ics-sources/`
- Добавить новую сущность `UserEntity` (login, passwordHash, role: 'admin'|'user')
- Переиспользовать существующую `AdminEntity` как auth-сущность (админ = admin с ролью admin)
- Создать `UsersModule`, `UsersController`, `UsersService` с CRUD для пользователей (только admin)
- Обновить `app.module.ts`: удалить ненужные imports, добавить UsersModule
- Обновить `main.ts`: убрать seed events, оставить только seed users/admin
- Упростить `package.json`: удалить `@nestjs/schedule`, `ical`, `nodemailer`
- Сохранить auth (JWT login) — он нужен для админ-панели

**Не трогать**: frontend, e2e, docker, scripts

---

### 2. 🎨 `cleanup-frontend` — Frontend: публичная страница + минимальная админка

**Ответственность**: Переделать UI — убрать календарь, сделать публичную страницу + админку управления пользователями.

**Задачи**:
- Создать `PublicView.vue` — публичная страница, показывает:
  - заголовок/описание (жестко заданные в коде или через API)
  - текущее количество пользователей (`/api/users/count`)
- Создать `UsersAdminView.vue` — админка:
  - таблица пользователей (login, role)
  - кнопка "Создать пользователя" (модальное окно с формой)
  - кнопка "Удалить" (для не-admin пользователей)
- Создать `api/users.ts` — axios client для `/api/users`
- Обновить `router/index.ts`:
  - `/` → PublicView (без auth)
  - `/login` → LoginView (без auth)
  - `/admin/users` → UsersAdminView (с auth)
- Обновить `App.vue` — убрать календарь, оставить header с кнопками навигации
- Очистить `useAuth.ts` — оставить только login/logout/checkAuth
- Удалить все календарные компоненты: Calendar.vue, CalendarDay.vue, CalendarMonth.vue, CalendarWeek.vue, SlotToolbar.vue, BookingModal.vue
- Удалить `useTheme.ts` — оставить базовую тему
- Удалить API-функции календаря из `api/events.ts` — оставить только auth

**Не трогать**: backend, e2e, docker

---

### 3. 🧪 `cleanup-e2e` — E2E тесты + CI

**Ответственность**: Создать/обновить e2e тесты и конфиги для нового приложения.

**Задачи**:
- Удалить все существующие тесты из `e2e/tests/`
- Создать `e2e/tests/basic.spec.ts`:
  - Тест 1: Вход в админ-панель (login → redirect to /admin/users)
  - Тест 2: Создание пользователя (POST /api/users с ролью user)
  - Тест 3: Проверка публичной страницы (GET /api/users/count → render на /)
- Убедиться, что `global-setup.ts` и `fixtures.ts` работают с новым API
- Обновить `playwright.config.mts` (корневой) и `playwright.config.ts` (e2e/)
- Обновить `package.json` на уровне корня

**Не трогать**: backend бизнес-логику, frontend компоненты

---

### 4. 🐳 `cleanup-docker` — Docker + деплой

**Ответственность**: Актуализировать Docker-файлы и скрипты деплоя.

**Задачи**:
- Обновить `docker/Dockerfile` — убедиться, что build stages корректны для нового кода
- Обновить `docker/docker-compose.yml` — оставить как есть (работает и для нового)
- Обновить `docker/docker-compose.e2e.yml` — актуализировать пути
- Создать `docker/docker-compose.nginx-proxy.yml` — пример с nginx-proxy + Let's Encrypt
- Создать `docker/env` — пример .env файла
- Создать `docker/env.example` — пример с комментариями для каждого поля
- Убедиться, что `apps/backend/.env.example` существует

---

### 5. 📚 `cleanup-docs` — Документация

**Ответственность**: Написать полную документацию.

**Задачи**:
- Переписать `README.md` — коротко о шаблоне, quick start
- Создать `docs/GETTING_STARTED.md`:
  - Что это за шаблон
  - Запуск с нуля через Docker (docker compose up)
  - Запуск с нуля без Docker (node + npm install + nginx + nginx-proxy)
  - Настройка переменных окружения
  - Создание первого администратора
- Удалить старые docs, не относящиеся к новому шаблону:
  - `docs/areas/calendar-ui-structure.md`
  - `docs/areas/notification-system.md`
  - `docs/areas/ics-sources.md`
  - `docs/tz/test-fixes-26-06-25.md`
  - `docs/deployment.md` (перезаписать новым содержанием из GETTING_STARTED)
  - `docs/context-index.md` (перезаписать)
- Создать `docs/areas/backend-api-structure.md` — новые API endpoints
- Создать `docs/areas/frontend-structure.md` — новая структура UI
- Создать `docs/areas/database-structure.md` — новые сущности (User, Admin)

---

### 6. 🤖 `cleanup-agents` — agents.md + скрипты

**Ответственность**: Обновить `agents.md`, скрипты разработки, документацию субагентов.

**Задачи**:
- Переписать `agents.md` (корневой):
  - Новая архитектура (без календаря)
  - Новые API endpoints
  - Команды dev/kill
  - E2E через CDP
  - Правила для агентов
  - Субагенты (browser-checker, docs-maintainer, test-runner, test-fixer) с рабочими примерами команд
- Переписать `.pi/agents/` конфигурации субагентов (если нужны)
- Обновить `scripts/log-runner.mjs` и `scripts/kill-service.mjs` — оставить как есть (работают)
- Убедиться, что `package.json` root имеет все нужные скрипты
- Создать `agents.md` для backend (`apps/backend/agents.md`) и frontend (`apps/frontend/agents.md`)

---

## Порядок выполнения

Рекомендуемый порядок для минимизации конфликтов:

1. **cleanup-backend** (ядро, влияет на всё остальное)
2. **cleanup-frontend** (зависит от backend API)
3. **cleanup-e2e** (зависит от backend + frontend)
4. **cleanup-docker** (зависит от готовых артефактов)
5. **cleanup-docs** (зависит от всего)
6. **cleanup-agents** (финальная полировка)

---

## Что НЕ делать

- Не менять структуру npm workspaces
- Не добавлять новые зависимости (оставить только необходимые)
- Не менять стиль кода (TypeScript, Nest.js, Vue 3)
- Не менять систему авторизации (JWT через Bearer token)
- Не менять систему логирования и PID-файлов
