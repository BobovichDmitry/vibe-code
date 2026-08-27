# Frontend Structure (Nuxt 3 SSR)

## Описание

Nuxt 3 (Vue 3 + Nitro-сервер, SSR, history-роутинг). Публичная страница (`/`)
рендерится на сервере: счётчик пользователей и брендинг приходят в HTML с сервера
(через `useAsyncData` + `useHead`). Админка: `/admin` (CRUD пользователей) и
`/admin/files` (управление файлами в S3). Авторизация — JWT в httpOnly cookie
(`auth_token`), обратно-совместимая с Bearer.

Frontend — отдельный сервис на порту **3000** (edge, за nginx-proxy). Backend
(Nest) — на **3001** (внутренний API); Nuxt проксирует `/api/**` → backend
через `routeRules`.

## Структура

```
apps/frontend/
├── nuxt.config.ts        # Конфиг: routeRules прокси /api, runtimeConfig, devServer 3000
├── app.vue                # Корень: глобальный брендинг (useHead) + NuxtLayout/NuxtPage
├── public/
│   └── favicon.svg        # Favicon (Nuxt отдаёт public/ автоматически; дефолт useBranding)
├── assets/css/style.css   # Tailwind directives + компонентные классы
├── pages/
│   ├── index.vue          # Публичная страница (SSR user count)
│   ├── login.vue          # Форма входа (middleware: guest)
│   └── admin/
│       ├── index.vue      # Пользователи CRUD (layout: admin, middleware: auth)
│       └── files.vue      # Файлы S3 (layout: admin, middleware: auth)
├── layouts/
│   ├── default.vue        # Глобальный хедер для не-admin страниц
│   └── admin.vue          # Сайдбар-админка (навигация + ThemeToggle + Выйти)
├── components/
│   └── ThemeToggle.vue    # Переключатель темы (light/system/dark)
├── composables/
│   ├── useApi.ts          # SSR-aware $fetch: client=/api (прокси), server=http://backend:3001/api
│   ├── useAuth.ts         # Cookie-auth (useCookie), login/logout/fetchUser
│   ├── useBranding.ts     # useAsyncData + useHead (title/favicon SSR)
│   └── useTheme.ts        # Тема (cookie, без FOUC)
├── middleware/
│   ├── auth.ts            # Защита /admin: редирект /login если нет cookie
│   └── guest.ts           # /login: редирект /admin если уже авторизован
├── plugins/
│   ├── theme.server.ts    # <html class="dark"> по cookie (SSR, без FOUC)
│   └── theme.client.ts    # matchMedia + localStorage-зеркало (client)
└── tsconfig.json          # extends .nuxt/tsconfig.json
```

## Роуты (file-based, history)

| Path | Page | Layout | Auth |
|------|------|--------|------|
| `/` | `pages/index.vue` | `default` | No |
| `/login` | `pages/login.vue` | `default` | guest |
| `/admin` | `pages/admin/index.vue` | `admin` | Yes (`middleware/auth`) |
| `/admin/files` | `pages/admin/files.vue` | `admin` | Yes (`middleware/auth`) |

Хеш-роутинга нет: переходы — real history (`/admin`, `/login`).

## API-клиент (useApi)

`composables/useApi.ts` — обёртка над `$fetch`:
- **Клиент**: `baseURL = runtimeConfig.public.apiBase` (`/api`) — браузер → свой
  origin → Nitro проксирует `/api/**` → backend (routeRules).
- **Сервер (SSR)**: `baseURL = runtimeConfig.apiBase` (`http://backend:3001/api`)
  — прямой server-to-server fetch, мимо CORS.
- При SSR проксирует `useRequestHeaders(['cookie'])` на backend (чтобы защищённые
  эндпоинты работали под SSR).
- Пути передаются БЕЗ `/api` (baseURL его содержит): `request('/users/count')`.

## Auth Flow (cookie-based, httpOnly + visible-флаг)

Два cookie (ставит backend на `/api/auth/login`):
- `auth_token` — httpOnly JWT (защищён от XSS; браузер отправляет автоматически на /api).
- `auth_logged_in` — visible-флаг `1` (без секрета; для UI «залогинен?» без сетевого запроса).

1. Форма → `useAuth().login()` → `POST /api/auth/login` → backend ставит оба cookie
   (и возвращает `{ access_token }` для обратной совместимости).
2. `useCookie('auth_logged_in')` — readable на клиенте (флаг); `useCookie('auth_token')`
   читается только на сервере (httpOnly).
3. `middleware/auth.ts`: проверяет флаг (клиент) / токен (сервер) + `user` state;
   при отсутствии user валидирует через `fetchUser()` (cookie отправляется автоматически).
4. `logout()` → `POST /api/auth/logout` (clearCookie оба) + локальная очистка.
5. Bearer-auth обратно совместим — старые клиенты/e2e работают через заголовок.

## Брендинг (SSR-safe)

`useBranding` грузит `GET /api/branding` через `useAsyncData` и применяет
`useHead({ title, link: [{ rel: 'icon', href }] })` — `<title>` и favicon приходят
в HTML с сервера (не пустой дефолт до гидратации).

## Тема (без FOUC)

- Cookie `theme_preference` (доступна на сервере).
- `plugins/theme.server.ts` ставит `<html class="dark">` в SSR-ответе.
- `plugins/theme.client.ts` синхронизирует с `matchMedia` + localStorage-зеркало.

## Composables: SSR-правила (module-level → keyed-singleton)

Nuxt-композаблы (`useState`, `computed` на их основе, `useCookie`, `useHead` и др.)
требуют активного Nuxt-контекста (setup/plugin/middleware). Вызывать их **на уровне
модуля** (вне функции) нельзя — SSR падает с «A composable that requires
access to the Nuxt instance was called outside of a plugin, Nuxt hook, Nuxt
middleware, or Vue setup function».

Поэтому `useTheme.ts` и `useAuth.ts` используют **keyed-singleton-геттеры**,
вызываемые лениво внутри composable-функции (где контекст уже есть):

```ts
// ❌ module-level — SSR-краш
const isDark = computed(() => theme.value === 'dark');
export { isDark };

// ✅ keyed-singleton, вызывается внутри Nuxt-контекста
function themeState() { return useState<ThemePreference>('theme', () => 'system'); }
export function useIsDarkTheme() {
  const theme = themeState();
  return computed(() => theme.value === 'dark');
}
```

`plugins/theme.server.ts` вызывает `useIsDarkTheme()` **внутри тела плагина**
(`defineNuxtPlugin(() => { ... })`), а не импортирует module-level ref.

## Loading-флаг + useAsyncData (паттерн)

Админ-страницы (`admin/index.vue`, `admin/files.vue`) первично грузят данные через
`await useAsyncData(...)`, а UI-спиннер завязан на отдельный `ref(true) loading`.
Т.к. `await` уже разрешён к моменту регистрации `watch`, `pending` там уже `false` —
если просто `watch(pending, ...)` без синхронизации, `loading` остаётся `true` навсегда
(бесконечный спиннер). Правильный паттерн:

```ts
const { data, pending, refresh } = await useAsyncData('key', fetcher);
// Синхронизируем текущее значение (после await pending уже false) + immediate,
// чтобы последующие refresh() корректно тогглили loading.
loading.value = pending.value;
watch(pending, (p) => { loading.value = p; }, { immediate: true });
```

Правило: Nuxt-композаблы (`useState`, `watch` за `pending` от `useAsyncData`) нельзя
«откладывать» после `await` без синхронизации текущего значения.

## Runtime config

| Переменная | Контекст | Значение |
|---|---|---|
| `NUXT_PUBLIC_API_BASE` | client | `/api` (отн., через Nitro прокси) |
| `NUXT_API_BASE` | server (SSR) | `http://backend:3001/api` (dev: `http://localhost:3001/api`) |

Чтобы вынести frontend на отдельный сервер — сменить `NUXT_API_BASE` на публичный
URL backend (без правок кода).

## Команды

| Команда | Описание |
|---|---|
| `npm run dev:frontend` | `nuxt dev` (порт 3000) |
| `npm run build:frontend` | `nuxt build` → `.output/` (Nitro server) |
| `npm run typecheck:frontend` | `nuxt typecheck` (vue-tsc --noEmit) |

## Common issues

1. **SSR падает на `document is not defined`** — доступ к `document`/`window`/
   `localStorage` только в `import.meta.client` / `typeof window !== 'undefined'`.
2. **SSR-краш «composable called outside...»** — `useState`/`computed` на уровне
   модуля. См. «Composables: SSR-правила»: выноси в keyed-геттеры внутри функции.
3. **Бесконечный спиннер на админ-странице** — `watch(pending, ...)` после
   `await useAsyncData` без синхронизации. См. «Loading-флаг + useAsyncData».
4. **FOUC темы** — проверь `plugins/theme.server.ts` (cookie → `<html class>`).
5. **404 на `/favicon.svg` + Vue Router warn** — favicon должен лежать в
   `apps/frontend/public/favicon.svg` (Nuxt отдаёт `public/` автоматически).
6. **401 на /admin под SSR** — cookie не проксируется: проверь `useApi` (useRequestHeaders).
7. **CORS на клиенте** — `CORS_ORIGIN` backend должен включать origin Nuxt.