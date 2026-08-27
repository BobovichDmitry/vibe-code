# Admin Panel

## Описание

Защищённая часть приложения (Nuxt). Layout `layouts/admin.vue` с **левым вертикальным сайдбаром** (по образцу agent-hosted): бренд-блок сверху, вертикальная навигация, внизу — `ThemeToggle`, бейдж логина и кнопка «Выйти». На `< lg` сайдбар открывается бургером как overlay-drawer. Две страницы: `pages/admin/index.vue` (CRUD пользователей) и `pages/admin/files.vue` (управление файлами в S3). Защита — Nuxt route middleware `middleware/auth.ts`.

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/frontend/layouts/admin.vue` | Admin layout с вертикальным сайдбаром (nav + ThemeToggle + logout). Применяется через `definePageMeta({ layout: 'admin' })` |
| `apps/frontend/pages/admin/index.vue` | Users CRUD table (страница `/admin`) |
| `apps/frontend/pages/admin/files.vue` | Файлы: таблица + фильтр/пагинация + загрузчик + скачать/удалить |
| `apps/frontend/components/ThemeToggle.vue` | Переключатель темы Light/System/Dark |
| `apps/frontend/middleware/auth.ts` | Route guard `/admin/**` — редирект на `/login` если нет cookie (сервер + клиент) |
| `apps/frontend/composables/useAuth.ts` | Auth state: cookie-based JWT (`auth_token` httpOnly + `auth_logged_in` visible-флаг), login/logout/fetchUser |
| `apps/frontend/composables/useBranding.ts` | Брендинг (title/favicon) — `useAsyncData` + `useHead`, SSR-safe |
| `apps/frontend/composables/useApi.ts` | SSR-aware `$fetch` к backend (клиент → `/api` через Nitro-прокси, сервер → `http://backend:3001/api`) |

## Маршруты

| Path | Page | Layout |
|------|------|--------|
| `/admin` | `pages/admin/index.vue` | `admin` |
| `/admin/files` | `pages/admin/files.vue` | `admin` |

Nuxt file-based routing (history, без хеша). `definePageMeta({ layout: 'admin', middleware: ['auth'] })` на каждой странице. `/admin` напрямую открывает список пользователей (раньше был редирект на `admin-users` в SPA — сейчас просто страница `index.vue`).

## Навигация

Сайдбар `layouts/admin.vue` содержит пункты «Пользователи» (`/admin`) и «Файлы» (`/admin/files`, иконка `ICON_FILES`). Активный пункт определяется **точным совпадением** пути (`route.path === path`) — каждая страница лист-роут.

## Guard (middleware/auth.ts)

Route middleware проверяет наличие сессии и редиректит на `/login`:
- **Сервер (SSR):** httpOnly cookie `auth_token` читается через `useCookie` из заголовков запроса.
- **Клиент:** httpOnly cookie не виден в JS, поэтому ориентируемся на visible-флаг `auth_logged_in` (ставится backend-ом на `/api/auth/login` вместе с `auth_token`; не содержит секрета — только сигнал «залогинен»).
- Если сигнала нет и `user` не загружен → `navigateTo('/login')`.
- Если `user` ещё не загружен — валидация через `fetchUser()` (запрос `/api/auth/me`; cookie отправляется автоматически браузером/Nitro-прокси). 401 → редирект на `/login`.

## Загрузка данных (важный SSR-паттерн)

Первичные данные приходят с сервера в HTML через `useAsyncData` (SSR) — не дёргается `onMounted`-фетч. При этом **отдельный `loading`-флаг нужно синхронизировать с `pending` из `useAsyncData`**:

```ts
const { data, pending, refresh } = await useAsyncData('key', () => api.request('/...'));
loading.value = pending.value;                                  // после await pending уже false
watch(pending, (p) => { loading.value = p; }, { immediate: true }); // для последующих refresh()
```

**Ловушка:** `watch(pending, ...)` регистрируется ПОСЛЕ `await useAsyncData`, когда `pending` уже `false`. Без `loading.value = pending.value` и `immediate: true` флаг `loading` (старт `true`) застревает навсегда → бесконечный спиннер. Этот баг был в `admin/index.vue` и `admin/files.vue` и исправлен.

## pages/admin/files.vue

- Таблица файлов из S3 с фильтром по `fileKey` (подстрока, case-insensitive, дебаунс) и пагинацией (`limit`/`offset`).
- Загрузчик: drag-and-drop + клик → `POST /api/files` (multipart `file`, рандомное имя на бэке). Прогресс-бар скачком 0→100 (ofetch не поддерживает `onUploadProgress` нативно — известная минорная UX-регрессия).
- Действия: скачать (presigned GET URL, открывается в новой вкладке), удалить (`DELETE /api/files?fileKey=`).

## Common issues

1. **Бесконечный спиннер в таблице** — проверь, что `loading` синхронизирован с `pending` useAsyncData (см. «Загрузка данных» выше). Если добавляешь новую админ-страницу с `useAsyncData` — не повторяй антипаттерн.
2. **SSR-краш «A composable that requires access to the Nuxt instance was called outside of a plugin/middleware/setup»** — `useState`/`computed`/`useCookie` вызываются на уровне модуля в composable. Перенеси их внутрь функции-композабла (keyed-singleton через `useState('key')` сохраняет семантику).
3. **Favicon 404 / Vue Router warn «No match found for /favicon.svg»** — файл должен лежать в `apps/frontend/public/` (Nuxt отдаёт `public/` автоматически). Без него запрос уходит в роутер.
4. **Файлы не загружаются** — S3 не настроен, проверьте `S3_*` env (см. `docs/areas/backend-api-structure.md`).
5. **404 при скачивании** — объект отсутствует в S3, но запись в БД есть (`inStorage=false`) — вызовите `update-meta` или удалите запись.
6. **Admin недоступен после логаута** — `logout` чистит `auth_token` + `auth_logged_in`; middleware/auth редиректит на `/login`. Корректное поведение.