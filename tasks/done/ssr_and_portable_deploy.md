Перевести frontend-часть на SSR (Nuxt 3). Также обновить механики авто-деплоя так, чтобы:
- не было проблем в будущем на других проектах;
- правки можно было вмержить в форки этого сетапа, и они продолжали штатно работать;
- после запуска `deploy.sh` форки продолжали штатную работу.

Во время разработки тестовый деплой НЕ нужен (тестовый сервер занят) — сначала реализовать всю механику. Деплой пользователь сделает сам руками.

> ✅ **Финализировано (2026-08-27).** Лежит в `## Todo`.

---

## Решения из диалога

1. **SSR-фреймворк — Nuxt 3.** Полная миграция `apps/frontend` (Vue SPA + hash-router + Vite) → Nuxt 3 (file-based routing, history-роутинг, Nitro-сервер). Хеш-роутинг убирается сразу (Nuxt по умолчанию на history). В `docs/` кладётся **гайд миграции** — инструкция для агента, чтобы он мог перенести на Nuxt всё приложение.
2. **Бэкенд остаётся отдельным сервисом Nest.js** (API на `/api`). Frontend (Nuxt SSR) и backend (Nest) — **два отдельных сервиса/процесса**, чтобы в будущем безболезненно вынести frontend на отдельный сервер. Nuxt проксирует `/api` на Nest (edge = Nuxt, Nest — внутренний).
3. **SSR-граница.** Вся публичная часть (`/`, любые будущие публичные страницы) — полноценный SSR (нормальная индексация). `/admin` — целевой ориентир тоже SSR (меню/хром админки приходят готовыми с сервера); **допустимый fallback** — admin как CSR-shell, если cookie-auth окажется рискованным. Auth под SSR → переход с `localStorage` JWT на **cookie-based JWT** (httpOnly cookie).

---

## Контекст (анализ кода)

### Текущее состояние (что есть)

- **Frontend** (`apps/frontend/`, Vite 6 + Vue 3 SPA):
  - Точка входа `src/main.ts` → `createApp(App).mount('#app')`; `index.html` с `<div id="app">`.
  - Роутер `src/router/index.ts` — `createWebHashHistory`, lazy-import компонентов, guard `requireAuth` на `/admin` (читает `localStorage.getItem('auth_token')`).
  - API-клиенты `src/api/{index,auth,users,files,branding}.ts` — axios, base из `import.meta.env.VITE_API_BASE_URL || '/'`; interceptor в `api/index.ts` клеит `Bearer` из `localStorage`.
  - Composables: `useAuth.ts` (JWT в `localStorage`, `fetchUser`/`login`/`logout`), `useBranding.ts` (манипулирует `document.title`/`<link rel=icon>` — **client-only**), `useTheme.ts` (localStorage `theme_preference` + `document.documentElement.classList` — **client-only**, уже частично SSR-safe через `typeof document === 'undefined'`).
  - Views: `PublicView.vue` (`onMounted` → `getUserCount()`), `LoginView.vue`, `admin/ManageUsersView.vue`, `admin/ManageFilesView.vue`; `layouts/AdminLayout.vue` (сайдбар, бургер-drawer на `< lg`).
  - `App.vue` — корень с глобальным хедером для не-admin, `router-view`; admin рендерится через `AdminLayout` напрямую.
- **Backend** (`apps/backend/`, Nest.js 11):
  - `main.ts` — `setGlobalPrefix('api')`, порт 3000, CORS из `CORS_ORIGIN`, раздаёт статику `apps/frontend/dist` через `useStaticAssets` + SPA-fallback на `index.html` (множественные candidate-пути).
  - `app.module.ts` — модули Database/Auth/Users/Branding/Files, сидит первого админа на пустой БД из `ADMIN_LOGIN`/`ADMIN_PASSWORD`.
  - Auth: `auth.controller.ts` (`/api/auth/login` → `{ access_token }`, `/me`, `/password`), `jwt-auth.guard.ts` — `ExtractJwt.fromAuthHeaderAsBearerToken()` (только Bearer, **cookie не извлекает**), `@Public()` декоратор.
  - Branding: `branding.controller.ts` — `GET /api/branding` (`@Public`, возвращает `{ title, faviconUrl }` из env `BRAND_TITLE`/`BRAND_FAVICON_URL`).
  - БД: TypeORM, SQLite (dev `synchronize`) / PostgreSQL (prod миграции, `DB_SYNCHRONIZE=false`).
- **Контейнер/деплой**:
  - `docker/Dockerfile` — multi-stage: `frontend-builder` (Vite build → `dist/`) + `backend-builder` (Nest build) → `production` (копирует `apps/frontend/dist` + `apps/backend/dist`, `CMD node apps/backend/dist/main.js`). **Один образ, один процесс, Nest раздаёт статику.**
  - `docker/docker-compose.prod.yml` — `app` (build, `VIRTUAL_HOST`/`LETSENCRYPT_*`, network `reverse-proxy`) + `postgres` (5432 не наружу). `env_file: ./env`.
  - `deploy.sh` (корень) — читает корневой `.env` (SSH_*, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_*, BRAND_*, `PROJECT_NAME`), sftp архива → авто-генерация `.app.secrets` (db_password, jwt_secret) → `ansible-playbook`. **Уже env-driven**, но есть форк-специфичные дефолты: `PROJECT_NAME="${PROJECT_NAME:-gmoreva-setup}"`.
  - `ansible/group_vars/all.yml` — `project_name: "gmoreva-setup"`, `project_dir: "/opt/vibesetup"` (рассинхрон с `PROJECT_DIR=/opt/$PROJECT_NAME`), `db_username: "vibesetup"`, `db_name: "vibesetup_db"`.
  - `ansible/templates/env.j2` — рендерит `docker/env` (PORT, CORS, DB, JWT, ADMIN, BRAND, VIRTUAL_HOST/LETSENCRYPT). `compose-proxy.yml.j2` — общий nginx-proxy + acme-companion (external-сеть `reverse-proxy`, один на сервер).
  - `ansible/playbook.yml` — roles: docker, nginx_proxy, app; healthcheck: `docker compose exec app wget http://localhost:3000/api/users/count` + `uri https://{{ domain }}/api/users/count`.
  - `.env.example` — `PROJECT_NAME="gmoreva-setup"` (реальный слаг зашит в пример).

### Что меняет SSR/Nuxt

- Frontend = **живой Node-процесс (Nitro)**, не статика. Текущая модель «Nest раздаёт `dist/`» исчезает.
- Hash-router → Nuxt file-based routing + history-роутинг. `router/index.ts`, `App.vue`-как-роутер, `requireAuth` guard — убираются; заменяются `pages/**`, `layouts/**`, `middleware/auth.ts`, `definePageMeta`.
- axios-клиенты → `$fetch`/`useFetch` (ofetch, SSR-aware) с baseURL из `useRuntimeConfig().public.apiBase` (клиент → `/api`, сервер (SSR) → `http://backend:3001/api`).
- `useBranding` (манипуляция `document`) → `useAsyncData('branding', () => $fetch('/api/branding'))` + `useHead({ title, link: [...] })` (SSR-safe, отдаёт `<head>` с сервера).
- `useTheme` (localStorage) → cookie `theme_preference` + Nuxt plugin / `useHead` для `<html class="dark">` (SSR-safe, без FOUC).
- Auth `localStorage.getItem('auth_token')` → `useCookie('auth_token')` (SSR-aware). Backend `JwtAuthGuard` → дополнительно `ExtractJwt.fromCookieField('auth_token')` (или `fromExtractors`). `/api/auth/login` ставит httpOnly cookie (опц. `secure`/`sameSite`).
- Порты: **backend → 3001** (внутренний API), **Nuxt → 3000** (edge, за nginx-proxy). И в dev, и в prod — консистентно. Затрагивает: `apps/backend/.env` (`PORT=3001`), `CORS_ORIGIN` (Nuxt origin), `e2e/.env` (`E2E_BASE_URL`→Nuxt:3000, `E2E_API_URL`→backend:3001/api), `vite.config.ts` proxy — уходит (Nuxt проксирует через nitro `routeRules`).
- Контейнер: **два сервиса** `frontend` (Nuxt, `VIRTUAL_HOST`, port 3000) + `backend` (Nest, port 3001, **без VIRTUAL_HOST**, internal) + `postgres`. Nuxt проксирует `/api/**` → `http://backend:3001` (nitro `routeRules`/`/server/routes`). nginx-proxy маршрутизирует только на `frontend`. Будущее «вынести frontend на отдельный сервер»: `frontend`-контейнер уезжает, `NUXT_PUBLIC_API_BASE`/server base указывает на URL backend.
- Dockerfile: split на `docker/Dockerfile.frontend` (Nuxt build → Nitro server) + `docker/Dockerfile.backend` (Nest build). compose билдит оба.
- Healthcheck ansible → `docker compose exec backend wget http://localhost:3001/api/users/count` (порт наружу не торчит).

### Переиспользуем

- API-эндпоинты Nest (auth/users/files/branding) — без изменений в логике; только auth-guard получает cookie-extractor + login ставит cookie.
- Сущности БД, миграции, сид админа, S3-модуль — без изменений.
- Tailwind/дизайн-система, `ThemeToggle.vue`, разметка views/layouts — переносятся в Nuxt-структуру почти as-is (Vue-SFC остаются).
- E2E-инфра (`e2e/fixtures.ts`) — структурно та же (CDP/headless), правятся только URL и auth-флоу под cookie.

### Чего нет / надо создать

- Nuxt-приложение в `apps/frontend/` (`nuxt.config.ts`, `pages/`, `layouts/`, `components/`, `composables/`, `middleware/`, `server/`, `assets/`, `app.vue`).
- SSR-aware composables (`useAuth`, `useBranding`, `useTheme`) на cookie/`useHead`.
- Cookie-auth на backend (`JwtAuthGuard` cookie-extractor, `/auth/login` set-cookie, опц. logout clear-cookie).
- Nitro-прокси `/api` → backend, runtime config `apiBase`.
- `docker/Dockerfile.frontend` + `docker/Dockerfile.backend`; обновлённые `docker-compose.{yml,prod.yml}`.
- Портабельные деплой-конфиги (deploy.sh, ansible group_vars, env.j2, .env.example) — без форк-специфичных дефолтов.
- Гайд миграции в `docs/`.
- Обновлённые e2e env + доки (`docs/areas/frontend-structure.md`, `deployment.md`, `agents.md`, `context-index.md`).

---

## Acceptance criteria

### Nuxt 3 / SSR-фронтенд
- [ ] `apps/frontend/` — Nuxt 3 приложение (Vue 3 + history-роутинг + Nitro). `vite.config.ts` и `src/router/index.ts` удалены; роутинг через `pages/**` (file-based).
- [ ] Маршруты сохранены: `/` (PublicView), `/login`, `/admin` (→ список пользователей), `/admin/files`. `/admin` guarded через `middleware/auth.ts`.
- [ ] Вся публичная часть рендерится на сервере: `PublicView` получает `userCount` через `useAsyncData`/`useFetch` (данные приходят в HTML с сервера, не дёргается `onMounted`-фетч). HTML ответа `/` содержит счётчики (без ожидания клиентского JS). Проверяется `curl http://localhost:3000/` — в HTML видны числа/скелетон с сервера.
- [ ] Брендинг: `useBranding` через `useAsyncData` + `useHead` — `<title>` и `<link rel="icon">` в SSR-ответе приходят с сервера (не пустой дефолт до гидратации).
- [ ] Тема (`useTheme`): SSR-safe, без FOUC — `<html>` уже имеет/не имеет `class="dark"` в серверном HTML (через cookie/plugin). localStorage уходит или дублируется в cookie.
- [ ] Auth: JWT в **httpOnly cookie** (`auth_token`). `/api/auth/login` ставит cookie, logout — чистит. `JwtAuthGuard` принимает токен из cookie **и** из Bearer (обратно-совместимо). `useAuth` — на `useCookie`, работает под SSR (не падает на `localStorage is not defined`).
- [ ] **Целевой ориентир:** `/admin` на SSR — `AdminLayout` (сайдбар/меню) приходит готовым с сервера в HTML. **Допустимый fallback** (если cookie-auth рискован): `/admin` отдаётся CSR-shell (Nuxt `ssr: false` для admin-роутов через `definePageMeta`/`routeRules`), меню рендерится на клиенте — но публичная часть при этом остаётся полноценным SSR. Выбор зафиксировать в файле задачи (как сделано) и в гайде.
- [ ] Хеш-роутинга нет нигде: `createWebHashHistory`/`#` в URL отсутствуют; переходы — real history (`/admin`, `/login`).
- [ ] API-клиенты (`api/*.ts`) переведены на `$fetch`/`useFetch` (или axios с SSR-safe base), baseURL из `useRuntimeConfig().public.apiBase`; серверный fetch идёт на `http://backend:3001/api`, клиентский — на `/api` (через Nitro-прокси).
- [ ] Файловый CRUD (`ManageFilesView`) сохраняет функционал (presigned-URL, multipart upload) после миграции.

### Разделение backend / frontend
- [ ] Backend (Nest) работает как самостоятельный сервис на порту **3001** (`PORT=3001` в `apps/backend/.env`, dev и prod). CORS_ORIGIN включает origin Nuxt (dev `http://localhost:3000`, prod `https://<DOMAIN>`).
- [ ] Nuxt (frontend) — отдельный сервис на порту **3000**, проксирует `/api/**` → `http://backend:3001` (nitro `routeRules` или `server/routes/api/[...].ts`). Внешний трафик идёт только на Nuxt; backend не имеет `VIRTUAL_HOST`.
- [ ] dev: `npm run dev` поднимает оба (`concurrently`); `dev:backend:log` / `dev:frontend:log` сохранены (лог-скрипты `scripts/log-runner.mjs` работают с Nuxt `nuxt dev`).
- [ ] При желании frontend можно вынести на отдельный сервер: достаточно сменить API base (runtime config / env) на URL backend — без правок кода.

### Деплой / портируемость по форкам
- [ ] `deploy.sh`: `PROJECT_NAME` **не имеет** форк-специфичного дефолта `gmoreva-setup` — либо required в `.env`, либо выводится из домена/имени репо с явным сообщением. Любые другие форк-специфичные строки убраны.
- [ ] `ansible/group_vars/all.yml`: `project_name`, `project_dir`, `db_username`, `db_name` — плейсхолдеры/выводятся из `project_name`, без хардкода `gmoreva-setup`/`vibesetup`. `project_dir` синхронен с `PROJECT_DIR=/opt/$PROJECT_NAME` из deploy.sh.
- [ ] `.env.example`: `PROJECT_NAME="my-project"` (плейсхолдер) + комментарий; реальные значения — в пользовательском `.env`.
- [ ] `ansible/templates/env.j2`: добавлены frontend-переменные (Nuxt API base, порты); `PORT=3001` для backend; CORS = `https://{{ domain }}`.
- [ ] `docker/docker-compose.prod.yml`: сервисы `frontend` (build `Dockerfile.frontend`, `VIRTUAL_HOST`/`LETSENCRYPT_*`, port 3000, depends_on backend) + `backend` (build `Dockerfile.backend`, port 3001, **без** VIRTUAL_HOST, internal) + `postgres` (без 5432 наружу). `frontend` подключён к `reverse-proxy`.
- [ ] `docker/docker-compose.yml` (dev): `frontend` + `backend` (+ postgres по желанию), порты для локальной разработки.
- [ ] `docker/Dockerfile.frontend` (multi-stage: deps → `nuxt build` → prod-образ с Nitro) и `docker/Dockerfile.backend` (deps → `nest build` → prod-образ). Старый `docker/Dockerfile` удалён или заменён.
- [ ] `ansible/roles/app`: билдит и поднимает оба сервиса (`docker compose -p <project> -f docker-compose.prod.yml up -d --build`); healthcheck — `docker compose exec backend wget -qO- http://localhost:3001/api/users/count` + внешний `https://{{ domain }}/api/users/count`.
- [ ] После `deploy.sh` на форке (с заполненным `.env`) проект поднимается штатно: HTTPS на DOMAIN, `/` рендерится с сервера, `/api/*` проксируется в backend, админ доступен. **Тестовый деплой не выполняется** (тестовый сервер занят) — только сборка/проверка типов локально.

### Документация
- [ ] **Гайд миграции на Nuxt** в `docs/` (напр. `docs/areas/nuxt-migration.md`): пошаговая инструкция для агента — маппинг старых файлов → Nuxt-структуры, портирование composables (auth→cookie, branding→useHead, theme→cookie), api-клиентов (axios→$fetch), роутинга, layout/middleware, e2e, деплоя; типичные SSR-ловушки (`document`/`localStorage` на сервере, FOUC, cookie-auth).
- [ ] `docs/areas/frontend-structure.md` переписан под Nuxt (структура `pages/layouts/components/composables/middleware/server`, роуты, API-клиенты, auth flow).
- [ ] `docs/deployment.md`, `docs/agents.md`, `AGENTS.md`, `docs/context-index.md` обновлены: два сервиса, порты 3000/3001, Dockerfile split, env-переменные Nuxt, портируемость.
- [ ] `apps/frontend/agents.md` (если есть) обновлён под Nuxt-команды (`nuxt dev`, `nuxt build`, typecheck).

### Edge-cases / корректность
- [ ] SSR не падает на `document is not defined` / `localStorage is not defined` (все client-only доступы за `import.meta.client` / `if (process.client)` / `typeof window !== 'undefined'`).
- [ ] Гидратация без mismatch-ворнингов в консоли (особенно тема и брендинг).
- [ ] Прямой переход на `/admin` без cookie → редирект на `/login` (и на сервере, и на клиенте).
- [ ] Logout чистит cookie; после logout `/admin` недоступен.
- [ ] Bearer-auth обратно-совместим (старые клиенты/e2e с Bearer работают, пока не переведены на cookie).

---

## Подсказки по реализации

- **Правки — фронт + бэк + деплой + доки.** Файлы (основные):
  - Frontend: `apps/frontend/**` (переустройство под Nuxt), `nuxt.config.ts`, `package.json`, `tsconfig.json`→Nuxt, `app.vue`, `pages/**`, `layouts/**`, `components/**`, `composables/**`, `middleware/**`, `server/**`, `assets/**`; удалить `vite.config.ts`, `src/router/index.ts`, `index.html`, `src/main.ts`, `src/App.vue` (перенести логику в `app.vue`/layouts).
  - Backend: `apps/backend/src/auth/jwt-auth.guard.ts` (cookie-extractor), `auth.controller.ts` (set/clear cookie на login/logout — добавить `logout` эндпоинт если нет), `main.ts` (убрать раздачу статики `frontend/dist` и SPA-fallback — Nest теперь чистый API на 3001; убрать `useStaticAssets`/SPA-блок), `apps/backend/.env` (`PORT=3001`, `CORS_ORIGIN`).
  - Docker: `docker/Dockerfile.frontend` (новый), `docker/Dockerfile.backend` (новый), удалить `docker/Dockerfile`; `docker/docker-compose.yml`, `docker/docker-compose.prod.yml`, `docker/env`, `docker/env` template.
  - Deploy: `deploy.sh`, `ansible/group_vars/all.yml`, `ansible/vars.example.yml`, `ansible/templates/env.j2`, `ansible/roles/app/tasks/main.yml`, `ansible/playbook.yml` (healthcheck).
  - E2E: `e2e/.env` (`E2E_BASE_URL=http://localhost:3000`, `E2E_API_URL=http://localhost:3001/api`), `e2e/tests/**` (auth-флоу под cookie — Playwright хранит cookies сам; убрать ручную запись в `localStorage` если было), `playwright.config.mts`.
  - Корень: `package.json` (скрипты `dev:frontend`→`nuxt dev`, `build:frontend`→`nuxt build`, тип-chek), `.env.example` (`PROJECT_NAME` плейсхолдер).
  - Доки: `docs/areas/nuxt-migration.md` (новый гайд), `docs/areas/frontend-structure.md`, `docs/deployment.md`, `docs/agents.md`, `AGENTS.md`, `docs/context-index.md`, `apps/frontend/agents.md`.
- **Переиспользовать**: SFC-разметку views/layouts/components перетащить почти as-is в Nuxt; Tailwind-конфиг/`assets/css` сохранить; API-контракты (`api/*.ts` типы) — типы оставить, реализацию перевести на `$fetch`.
- **Nuxt runtime config**: в `nuxt.config.ts` — `runtimeConfig: { public: { apiBase: '/api' }, apiBase: process.env.NUXT_API_BASE || 'http://backend:3001/api' }`; серверный fetch использует `useRuntimeConfig().apiBase` (внутренний), клиентский — `public.apiBase` (`/api` через Nitro-прокси). Nitro `routeRules: { '/api/**': { proxy: 'http://backend:3001/api/**' } }` — самый простой вариант прокси.
- **Cookie-auth**: `JwtAuthGuard` — `jwtFromRequest: ExtractJwt.fromExtractors([ExtractJwt.fromAuthHeaderAsBearerToken(), (req) => req?.cookies?.auth_token])`; login: `res.cookie('auth_token', token, { httpOnly: true, sameSite: 'lax', secure: env prod })`; добавить `POST /api/auth/logout` (`res.clearCookie`). Nest: `app.use(cookieParser())` в `main.ts` + `cookie-parser` dep.
- **Тема без FOUC**: Nuxt plugin `plugins/theme.server.ts` читает cookie → ставит `useHead({ htmlAttrs: { class: isDark ? 'dark' : '' } })` на сервере; клиентский plugin синхронизирует с localStorage/system.
- **Брендинг**: `useAsyncData('branding', () => $fetch('/api/branding'))` в `app.vue`/layouts + `useHead({ title: branding.title, link: [{ rel: 'icon', href: branding.faviconUrl }] })`.
- **e2e auth под cookie**: Playwright `context` хранит cookies после `POST /api/auth/login` автоматически — тесты логинятся через API/форму, дальше `/admin` доступен без ручной записи в `localStorage`.
- **Порты — консистентность**: backend 3001 везде (dev `.env`, prod `env.j2`, e2e, доки). Nuxt 3000 везде. nginx-proxy → только `frontend:3000`.
- **Портируемость deploy**: вынести ВСЕ форк-специфичные строки в `.env`/`vars.yml`; `group_vars/all.yml` — только плейсхолдеры/выводимые. Проверить `grep -rn "gmoreva-setup\|vibesetup" deploy.sh ansible/ docker/ .env.example` — не должно остаться хардкода (только плейсхолдеры/комментарии).
- **На что обратить внимание**: CORS_ORIGIN должен включать Nuxt-origin (и dev `http://localhost:3000`, и prod домен); SSR-фетч с сервера идёт **мимо** CORS (server-to-server), но клиентский fetch — через CORS; не сломать миграции БД (backend стартует с `DB_SYNCHRONIZE=false` + `migrationsRun`); `FRONTEND_DIST` env в `main.ts` — убрать (статика больше не раздаётся).

## Проверка

- `npx nuxi typecheck` (или `npx vue-tsc --noEmit`) в `apps/frontend` — без ошибок.
- `npx tsc --noEmit` в `apps/backend` — без ошибок.
- `npm run build` (frontend `nuxt build` + backend `nest build`) — без ошибок; `docker build -f docker/Dockerfile.frontend .` и `docker/Dockerfile.backend` — собираются (если Docker доступен; иначе пропустить).
- `grep -rn "gmoreva-setup\|vibesetup_db\|/opt/vibesetup" deploy.sh ansible/ docker/ .env.example` — только плейсхолдеры/комментарии (нет реальных хардкодов).
- **dev-серверы и e2e НЕ запускать** (по правилам проекта) — это делает пользователь. Тестовый деплой НЕ делать (тестовый сервер занят).
---

## Реализация (2026-08-27)

Реализовано субагентом `code-solver` (чистый контекст), проверено основным агентом.

### Что сделано

**Backend (Nest) — чистый API на порту 3001:**
- `apps/backend/src/main.ts` — убрана раздача статики `frontend/dist` + SPA-fallback; добавлен `cookie-parser`; дефолтный порт 3001.
- `auth/jwt-auth.guard.ts` + `jwt.strategy.ts` — `ExtractJwt.fromExtractors([Bearer, cookie.auth_token])` (обратно-совместимый cookie+Bearer).
- `auth/auth.controller.ts` — `/login` ставит httpOnly `auth_token` + visible-флаг `auth_logged_in=1`; добавлен `POST /api/auth/logout` (clearCookie).
- `apps/backend/.env` / `.env.example` — `PORT=3001`, `CORS_ORIGIN=http://localhost:3000`, `COOKIE_SECURE`.
- `package.json` — добавлены `cookie-parser`, `@types/cookie-parser`, `typecheck`.

**Frontend — миграция на Nuxt 3 (SSR, порт 3000):**
- Удалены `vite.config.ts`, `index.html`, `src/main.ts`, `src/App.vue`, `src/router/`, `src/api/`, `postcss.config.js`, `dist/`.
- Создана Nuxt-структура: `nuxt.config.ts`, `app.vue`, `pages/` (index, login, admin/index, admin/files), `layouts/` (default, admin), `components/ThemeToggle.vue`, `composables/` (useApi, useAuth, useBranding, useTheme), `middleware/` (auth, guest), `plugins/` (theme.server, theme.client), `assets/css/style.css`.
- `nuxt.config.ts` — `routeRules: { '/api/**': { proxy: 'http://backend:3001/api/**' } }`, `runtimeConfig` (public.apiBase=`/api`, server apiBase=`http://backend:3001/api`), `devServer` 3000.
- `useApi` — SSR-aware `$fetch`: клиент → `/api` (через Nitro-прокси), сервер → прямой fetch к backend с прокси `useRequestHeaders(['cookie'])`.
- SSR data fetching через `useAsyncData` (user-count, branding, admin-таблицы); `useHead` для title/favicon (приходят в HTML с сервера).
- Auth: cookie-based (`auth_token` httpOnly + `auth_logged_in` visible), `useCookie`+`useState`, `middleware/auth` (сервер+клиент), `fetchUser`.
- Тема: cookie + server-plugin ставит `<html class="dark">` в SSR (без FOUC).
- History-роутинг (без `#`).

**Docker — split на два сервиса:**
- `docker/Dockerfile.frontend` (Nuxt build → Nitro, 3000) + `docker/Dockerfile.backend` (Nest, 3001); старый `docker/Dockerfile` удалён.
- `docker-compose.yml` (dev): frontend + backend + postgres (порты проброшены).
- `docker-compose.prod.yml`: frontend (VIRTUAL_HOST, 3000, reverse-proxy) + backend (без VIRTUAL_HOST, 3001, internal) + postgres (5432 не наружу). `NUXT_API_BASE=http://backend:3001/api`.

**Деплой — портируемость по форкам:**
- `deploy.sh` — `PROJECT_NAME` обязателен (нет дефолта `gmoreva-setup`); db_username/db_name выводятся из PROJECT_NAME; логи-команда → `frontend backend`.
- `ansible/group_vars/all.yml`, `vars.example.yml`, `inventory.ini`, `README.md` — плейсхолдеры, `project_dir`/`db_username`/`db_name` выводятся из `project_name`.
- `ansible/templates/env.j2` — PORT=3001, CORS, COOKIE_SECURE, frontend-переменные.
- `ansible/roles/app/tasks/main.yml` — build/up обоих сервисов.
- `ansible/playbook.yml` — healthcheck на `backend:3001`.
- `.env.example` (корень) — `PROJECT_NAME="my-project"`.

**E2E:** `e2e/.env` (E2E_BASE_URL=:3000, E2E_API_URL=:3001/api); `e2e/tests/basic.spec.ts` — history-роутинг (без `#`), cookie-auth (Playwright хранит cookie автоматически).

**Документация:** новый гайд `docs/areas/nuxt-migration.md`; переписан `docs/areas/frontend-structure.md`; обновлены `docs/deployment.md`, `docs/agents.md`, `docs/context-index.md`, `docs/project-overview.md`, `AGENTS.md`, `apps/frontend/agents.md`, `apps/backend/agents.md`.

**Root:** `package.json` — `typecheck`/`typecheck:frontend`/`typecheck:backend`, `build:frontend`→`nuxt build`; `.gitignore` — `.output/`, `.nuxt/`.

### Ключевые решения / trade-off
- Cookie-auth: httpOnly `auth_token` (защищённый) + visible `auth_logged_in` (для SSR-проверки наличия сессии без чтения httpOnly на клиенте). Bearer сохранён — обратно-совместимо со старыми клиентами/e2e.
- `/api` проксируется через Nitro `routeRules` (edge=Nuxt, backend internal). Будущее вынесение frontend на отдельный сервер — сменой `NUXT_API_BASE`/runtime config.
- `/admin` — SSR (меню/хром с сервера), как целевой ориентир задачи; fallback CSR-shell не потребовался.
- Прогресс-бар multipart-загрузки файлов: ofetch не поддерживает `onUploadProgress` нативно — прогресс скачком 0→100 в конце. Сама загрузка работает. Минорная UX-регрессия (TODO: опционально нативный XHR/`@vueuse/core`).

### Как проверено
- backend `npx tsc --noEmit` → exit 0.
- frontend `npm run typecheck` (`nuxt typecheck`) → exit 0.
- frontend `npm run build` (`nuxt build`) → exit 0, собран Nitro-сервер `.output/server/index.mjs`.
- backend `npm run build` (`nest build`) → exit 0.
- `grep -rn "gmoreva-setup\|vibesetup_db\|/opt/vibesetup" deploy.sh ansible/ docker/ .env.example` → чисто (только плейсхолдеры).
- dev-серверы и e2e НЕ запускались (по правилам проекта). Тестовый деплой НЕ выполнялся (тестовый сервер занят).

### Остаточные риски / TODO
- Runtime-поведение SSR (cookie-прокси, гидратация) не проверено вживую — требует ручного запуска пользователем (`npm run dev` + e2e через `@test-runner`).
- Прогресс-бар загрузки файлов (см. trade-off) — минорная UX-регрессия.
- `docker-compose.nginx-proxy.yml` (legacy-вариант) оставлен as-is — не входит в активный деплой-флоу; при желании адаптировать под split-сервисы отдельной задачей.
- Нитро production-порт задаётся `NITRO_PORT` env в Dockerfile (3000).
