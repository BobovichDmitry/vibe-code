# Гайд миграции на Nuxt 3 (SSR)

Пошаговая инструкция для агента — перенос Vue SPA (Vite + hash-router + axios +
localStorage JWT) на Nuxt 3 (file-based routing, history-роутинг, Nitro-сервер,
cookie-auth). Этот гайд описывает уже выполненную миграцию и служит референсом
для будущих форков/правок.

> Контекст: VibeSetup UI перешёл с Vite SPA на Nuxt 3 SSR. Backend (Nest) остаётся
> отдельным сервисом на порту **3001** (внутренний API); frontend (Nuxt SSR) — на
> **3000** (edge, за nginx-proxy). Nuxt проксирует `/api/**` → backend.

---

## Архитектура «после»

```
браузер ──HTTPS──▶ nginx-proxy ──▶ frontend (Nuxt/Nitro, :3000)
                                        │ /api/** (routeRules proxy)
                                        ▼
                                 backend (Nest, :3001, внутренний)
                                        │
                                 postgres (внутренний)
```

- **Публичная часть (`/`)** — полноценный SSR: счётчики/брендинг приходят в HTML
  с сервера (`useAsyncData`/`useFetch` + `useHead`).
- **`/admin`** — SSR (меню/хром админки отрисовываются на сервере). Защита —
  `middleware/auth.ts` (читает httpOnly cookie, при SSR валидирует через backend).
  Допустимый fallback (если cookie-auth рискован): `routeRules: { '/admin/**': { ssr: false } }`.
- **Auth** — JWT в httpOnly cookie `auth_token`. Backend ставит cookie на
  `/api/auth/login` и читает его в `JwtAuthGuard` **наряду** с Bearer
  (обратно-совместимо: старые клиенты/e2e с Bearer работают).

---

## Маппинг старых файлов → Nuxt-структура

| Было (Vite SPA) | Стало (Nuxt 3) |
|---|---|
| `vite.config.ts` | удалён → `nuxt.config.ts` (proxy через `routeRules`) |
| `index.html` | удалён → `app.vue` + `nuxt.config.ts` `app.head` |
| `src/main.ts` | удалён → `app.vue` (точка входа Nuxt) |
| `src/App.vue` | `app.vue` (корень) + `layouts/default.vue` |
| `src/router/index.ts` | удалён → `pages/**` (file-based routing) |
| `src/views/PublicView.vue` | `pages/index.vue` |
| `src/views/LoginView.vue` | `pages/login.vue` |
| `src/views/admin/ManageUsersView.vue` | `pages/admin/index.vue` |
| `src/views/admin/ManageFilesView.vue` | `pages/admin/files.vue` |
| `src/layouts/AdminLayout.vue` | `layouts/admin.vue` |
| `src/components/ThemeToggle.vue` | `components/ThemeToggle.vue` |
| `src/composables/useAuth.ts` | `composables/useAuth.ts` (cookie) |
| `src/composables/useBranding.ts` | `composables/useBranding.ts` (useHead) |
| `src/composables/useTheme.ts` | `composables/useTheme.ts` + `plugins/theme.{server,client}.ts` |
| `src/api/*.ts` (axios) | `composables/useApi.ts` ($fetch, SSR-aware) |
| `src/style.css` | `assets/css/style.css` |

---

## Портирование ключевых механик

### 1. Роутинг

- `createWebHashHistory` → **убрать**. Nuxt использует history-роутинг по умолчанию.
- `routes` массив → `pages/**` (file-based). `/admin` с children → `pages/admin/index.vue`
  + `pages/admin/files.vue`.
- Guard `requireAuth` → `middleware/auth.ts` + `definePageMeta({ middleware: ['auth'] })`.
- `router-link` → `NuxtLink`, `router.push` → `navigateTo`, `useRoute/useRouter` →
  Nuxt-эквиваленты (`useRoute()`, `navigateTo()`).

### 2. API-клиенты (axios → $fetch)

- axios-инстанс с interceptor'ом Bearer → `composables/useApi.ts` на `$fetch`/`useFetch`.
- baseURL:
  - **клиент**: `runtimeConfig.public.apiBase` (`/api`) — браузер → свой origin →
    Nitro проксирует (`routeRules: { '/api/**': { proxy } }`);
  - **сервер (SSR)**: `runtimeConfig.apiBase` (`http://backend:3001/api`) — прямой
    server-to-server fetch, мимо CORS.
- При SSR проксируем cookie входящего запроса на backend (`useRequestHeaders(['cookie'])`),
  чтобы защищённые роуты работали под SSR.

### 3. Auth (localStorage JWT → httpOnly cookie)

- `localStorage.getItem('auth_token')` → httpOnly cookie `auth_token` (JWT).
  **Важно**: httpOnly cookie НЕ читается `useCookie` на клиенте (document.cookie
  его не видит). Поэтому backend ставит второй cookie `auth_logged_in=1`
  (НЕ httpOnly, без секрета — только флаг присутствия) для UI-индикаторов
  «залогинен?» без сетевого запроса. Сам JWT остаётся httpOnly (защищён от XSS).
- Backend `JwtAuthGuard`: `ExtractJwt.fromExtractors([fromAuthHeaderAsBearerToken(), (req) => req?.cookies?.auth_token])`.
- `/api/auth/login` ставит ОБА cookie (`res.cookie('auth_token', ..., {httpOnly:true})`
  + `res.cookie('auth_logged_in', '1', {httpOnly:false})`).
- Добавлен `POST /api/auth/logout` (`res.clearCookie` для обоих).
- `cookie-parser` подключается в `main.ts` (`app.use(cookieParser())`).
- `COOKIE_SECURE=true` в проде (HTTPS). В dev — `false`.
- `useAuth`: `isAuthenticated = !!user.value || loggedInFlag === '1'`.
  `middleware/auth` проверяет флаг (клиент) / токен (сервер), при отсутствии user
  валидирует через `fetchUser()` (cookie отправляется автоматически).

### 4. Брендинг (DOM-манипуляция → useHead)

- `document.title` / `link[rel=icon]` → `useAsyncData('branding', ...)` + `useHead({ title, link })`.
- Данные приходят с сервера в HTML (нет пустого дефолта до гидратации).

### 5. Тема (localStorage → cookie + plugin, без FOUC)

- localStorage `theme_preference` → cookie `theme_preference` (доступна на сервере).
- `plugins/theme.server.ts` читает cookie → `useHead({ htmlAttrs: { class: isDark ? 'dark' : '' } })`
  — `<html>` уже имеет класс в серверном HTML (без FOUC).
- `plugins/theme.client.ts` синхронизирует с `matchMedia` + зеркалом localStorage.
- Все `document`/`window` доступы — за `import.meta.client` / `typeof document !== 'undefined'`.

### 6. Деплой (один процесс → два сервиса)

- Старая модель «Nest раздаёт `frontend/dist`» — **убрана**. `main.ts` больше не
  делает `useStaticAssets` / SPA-fallback.
- `docker/Dockerfile` (один образ) → `Dockerfile.frontend` + `Dockerfile.backend`.
- `docker-compose.prod.yml`: `frontend` (VIRTUAL_HOST, 3000) + `backend` (без
  VIRTUAL_HOST, 3001, internal) + `postgres`.
- Nuxt проксирует `/api/**` → `http://backend:3001` (`routeRules`, цель из `NUXT_API_BASE`).
- Healthcheck ansible: `docker compose exec backend wget -qO- http://localhost:3001/api/users/count`.

### 7. E2E

- `E2E_BASE_URL=http://localhost:3000` (Nuxt), `E2E_API_URL=http://localhost:3001/api` (Nest).
- History-роутинг: URL без `#` (`/login`, `/admin`).
- Cookie-auth: Playwright `context` хранит cookie после `POST /api/auth/login`
  автоматически — ручная запись в `localStorage` не нужна.

---

## Типичные SSR-ловушки

1. **`document is not defined` / `localStorage is not defined`** — любой доступ к
   `document`/`window`/`localStorage` на сервере падает. Оборачивать в
   `import.meta.client` / `if (process.client)` / `typeof window !== 'undefined'`.
2. **FOUC (мигание темы)** — если тема применяется только на клиенте, сервер
   отдаёт светлую, потом переключается на тёмную. Решение: cookie + server-plugin
   ставит `<html class="dark">` в SSR.
3. **Hydration mismatch** — сервер и клиент рендерят разное (например, разные
   `Date.now()` или случайное значение). Делать данные детерминированными на SSR
   или рендерить только на клиенте (`<ClientOnly>`).
4. **CORS при SSR** — server-to-server fetch идёт **мимо** CORS (браузер не участвует).
   CORS важен только для клиентского fetch (браузер → Nuxt → прокси).
5. **Cookie при SSR fetch** — чтобы защищённые эндпоинты работали под SSR,
   проксируйте `useRequestHeaders(['cookie'])` в заголовки запроса к backend.
6. **Пустой `<head>` до гидратации** — брендинг/title через `useHead`, а не через
   `document.title` в `onMounted`.
7. **Module-level Nuxt-композаблы → SSR-краш** — `useState`/`computed`/`useCookie`
   на уровне модуля (вне функции) падают с «A composable that requires access to
   the Nuxt instance was called outside of a plugin, Nuxt hook, Nuxt middleware,
   or Vue setup function». Решение: keyed-singleton-геттеры, вызываемые лениво
   внутри composable-функции (`function themeState() { return useState('theme', ...) }`).
   Плагины (`theme.server.ts`) вызывают композаблы **внутри тела**
   `defineNuxtPlugin(() => { ... })`, а не импортируют module-level ref.
8. **Бесконечный спиннер: `watch(pending)` после `await useAsyncData`** —
   `await useAsyncData` уже разрешён к моменту регистрации `watch`, `pending`
   уже `false`. Если UI-спиннер (`ref(true) loading`) синхронизировать только
   через `watch(pending, ...)`, `loading` застревает `true` навсегда. Решение:
   после `await` — `loading.value = pending.value;` (текущее значение) **и**
   `watch(pending, (p) => { loading.value = p; }, { immediate: true });`. Это же
   правило для любых Nuxt-композаблов, «отложенных» после `await`.
9. **Favicon 404 + Vue Router warn** — `/favicon.svg` должен лежать в
   `apps/frontend/public/favicon.svg`; Nuxt раздаёт `public/` автоматически.
   Иначе `/favicon.svg` даёт 404 и Vue Router warn в консоли. `useBranding`
   дефолтный фавикон — `DEFAULT_FAVICON = '/favicon.svg'`.

---

## Портируемость по форкам

- Никаких хардкодов слага проекта (`gmoreva-setup`, `vibesetup_db`, `/opt/vibesetup`).
- `PROJECT_NAME` — обязателен в `.env` (нет дефолта). `project_dir`/`archive_path`/
  `db_username`/`db_name` выводятся из `project_name`.
- `group_vars/all.yml` — плейсхолдеры/выводимые; реальные значения — в `vars.yml`.
- Чтобы вынести frontend на отдельный сервер: достаточно сменить `NUXT_API_BASE`
  на публичный URL backend — без правок кода.

## Проверка после миграции

- `npx nuxi typecheck` (apps/frontend) — без ошибок.
- `npx tsc --noEmit` (apps/backend) — без ошибок.
- `npm run build` (nuxt build + nest build) — без ошибок.
- `grep -rn "gmoreva-setup\|vibesetup_db\|/opt/vibesetup" deploy.sh ansible/ docker/ .env.example`
  — только плейсхолдеры/комментарии (нет хардкода).
- dev-серверы и e2e запускает пользователь (агент НЕ запускает).