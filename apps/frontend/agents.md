# Frontend Agent Guide (Nuxt 3 SSR)

## Stack

- **Nuxt 3** (Vue 3 + Nitro-сервер, SSR, history-роутинг)
- **Tailwind CSS**
- **$fetch / useFetch / useAsyncData** (ofetch, SSR-aware) — вместо axios
- **Cookie-auth** (httpOnly cookie `auth_token`) — вместо localStorage JWT
- **Nitro routeRules** — прокси `/api/**` → backend (Nest, 3001)
- monorepo workspace `apps/frontend`, порт **3000**

## Structure

```
apps/frontend/
├── nuxt.config.ts          # routeRules прокси /api, runtimeConfig, devServer 3000
├── app.vue                  # Корень: глобальный брендинг (useHead) + NuxtLayout/NuxtPage
├── assets/css/style.css     # Tailwind directives + компонентные классы
├── pages/                   # file-based routing (history)
│   ├── index.vue            # Публичная страница (SSR user count)
│   ├── login.vue            # Форма входа (middleware: guest)
│   └── admin/
│       ├── index.vue        # Пользователи CRUD (layout: admin, middleware: auth)
│       └── files.vue        # Файлы S3 (layout: admin, middleware: auth)
├── layouts/
│   ├── default.vue          # Глобальный хедер для не-admin страниц
│   └── admin.vue            # Сайдбар-админка
├── components/
│   └── ThemeToggle.vue      # Переключатель темы
├── composables/             # авто-импорт Nuxt
│   ├── useApi.ts            # SSR-aware $fetch (client=/api, server=http://backend:3001/api)
│   ├── useAuth.ts           # Cookie-auth (useCookie), login/logout/fetchUser
│   ├── useBranding.ts       # useAsyncData + useHead (SSR title/favicon)
│   └── useTheme.ts          # Тема (cookie, без FOUC)
├── middleware/              # авто-импорт как 'auth', 'guest'
│   ├── auth.ts              # Защита /admin: редирект /login если нет cookie
│   └── guest.ts             # /login: редирект /admin если авторизован
├── plugins/
│   ├── theme.server.ts      # <html class="dark"> по cookie (SSR)
│   └── theme.client.ts      # matchMedia + localStorage-зеркало (client)
└── tsconfig.json            # extends .nuxt/tsconfig.json
```

## Routes (file-based, history)

| Path | Page | Layout | Auth |
|------|------|--------|------|
| `/` | `pages/index.vue` | `default` | No |
| `/login` | `pages/login.vue` | `default` | guest |
| `/admin` | `pages/admin/index.vue` | `admin` | Yes (`middleware/auth`) |
| `/admin/files` | `pages/admin/files.vue` | `admin` | Yes (`middleware/auth`) |

Хеш-роутинга нет: переходы — real history. Guard — `middleware/auth.ts`.

## API Client (useApi)

`composables/useApi.ts` — обёртка над `$fetch`:
- **Клиент**: `baseURL = runtimeConfig.public.apiBase` (`/api`) → Nitro прокси → backend.
- **Сервер (SSR)**: `baseURL = runtimeConfig.apiBase` (`http://backend:3001/api`) —
  прямой server-to-server fetch, мимо CORS.
- При SSR проксирует `useRequestHeaders(['cookie'])` на backend.
- Пути БЕЗ `/api` (baseURL содержит): `request('/users/count')`.

## Auth Flow (cookie, httpOnly + visible-флаг)

Два cookie (ставит backend на `/api/auth/login`):
- `auth_token` — httpOnly JWT (защищён от XSS; браузер отправляет автоматически).
- `auth_logged_in` — visible-флаг `1` (без секрета; для UI «залогинен?» без запроса).

1. `useAuth().login()` → `POST /api/auth/login` → backend ставит оба cookie
   (и возвращает `{ access_token }` для обратной совместимости).
2. `useCookie('auth_logged_in')` — readable на клиенте (флаг);
   `useCookie('auth_token')` — только на сервере (httpOnly).
3. `middleware/auth.ts` проверяет флаг/токен + `user` state; при отсутствии user
   валидирует через `fetchUser()` (cookie отправляется автоматически).
4. `logout()` → `POST /api/auth/logout` (clearCookie оба).
5. Bearer-auth обратно совместим (старые клиенты/e2e).

## Брендинг / Тема (SSR-safe)

- `useBranding` — `useAsyncData('branding')` + `useHead({ title, link })` (HTML с сервера).
- `useTheme` + `plugins/theme.{server,client}.ts` — cookie `theme_preference`,
  `<html class="dark">` в SSR-ответе (без FOUC).

## Runtime Config (env)

| Var | Контекст | Default | Описание |
|-----|----------|---------|----------|
| `NUXT_PUBLIC_API_BASE` | client | `/api` | Клиентский base (через Nitro прокси) |
| `NUXT_API_BASE` | server (SSR) | `http://backend:3001/api` | Серверный base (прямой fetch) |

## Commands

| Command | Description |
|---------|-------------|
| `npm run dev:frontend:log` | Start `nuxt dev` (порт 3000, с логированием) |
| `npm run kill:frontend` | Kill frontend process tree |
| `npm run build:frontend` | `nuxt build` → `.output/` (Nitro server) |
| `npm run typecheck:frontend` | `nuxt typecheck` (vue-tsc --noEmit) |

## Critical Gotchas (SSR)

1. **`document is not defined` / `localStorage is not defined`** — любой доступ к
   `document`/`window`/`localStorage` только в `import.meta.client` /
   `typeof window !== 'undefined'`.
2. **FOUC темы** — cookie + server-plugin ставят `<html class>` в SSR.
3. **Hydration mismatch** — детерминированные данные на SSR (без `Date.now()`/
   случайных значений в рендере).
4. **Cookie при SSR fetch** — `useApi` проксирует `useRequestHeaders(['cookie'])`.
5. **CORS** — только для клиентского fetch; SSR-фетч идёт мимо CORS.
6. **Хеш-роутинга нет** — URL без `#` (`/admin`, `/login`).

## Logs

- `logs/frontend.log` — текущий лог (ротация 10MB)
- `logs/frontend.pid` — PID (есть = запущен)