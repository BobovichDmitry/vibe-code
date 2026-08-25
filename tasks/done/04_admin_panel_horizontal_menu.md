Рестайл админ-панели под дизайн-систему `agent-hosted` (бренд-блок в шапке, composable `useBranding`, компонент `ThemeToggle.vue`, иконки в пунктах меню, единая Tailwind-эстетика), но **с горизонтальным меню навигации** (вертикальный сайдбар референса НЕ берётся — пользователь явно просит горизонтальное).

> **Решения по вопросам:** Q2 — добавляется минимальный публичный эндпоинт `GET /api/branding` (env `BRAND_TITLE`/`BRAND_FAVICON_URL`, без БД), `useBranding` грузит из него с дефолт-фолбэком.

---

## Контекст (анализ кода)

Текущая `apps/frontend/src/layouts/AdminLayout.vue` уже имеет горизонтальное меню (`<nav class="flex gap-2 overflow-x-auto">` с кнопками-пунктами), шапку с лого-блоком, `useTheme` (Light/System/Dark + toggle), кнопку «Выйти», `useAuth`. После задачи 02 в `navItems` останется только «Пользователи».

Референс `agent-hosted/apps/frontend/src/layouts/AdminLayout.vue` — **вертикальный** сайдбар (НЕ брать раскладку), но берём оттуда **дизайн-систему/паттерны**:

- Composable `apps/frontend/src/composables/useBranding.ts` — singleton, грузит `GET /api/settings/branding` (публичный, без JWT), реактивные `title`/`faviconUrl`, применяет к `document.title` и `<link rel="icon">`. В референсе бренд-настройки хранятся в `settings` — в нашем каркасе `settings`-модуль удаляется (задача 02), поэтому бренд реализуем **минимальным публичным эндпоинтом `GET /api/branding`** из env `BRAND_TITLE`/`BRAND_FAVICON_URL` без БД (решение Q2).
- Компонент `apps/frontend/src/components/ThemeToggle.vue` — вынесенный из разметки переключатель темы (segmented Light/System/Dark + icon-toggle), переиспользуется в шапке. Сейчас в vibecode тема зашита прямо в `AdminLayout.vue` — вынести в компонент.
- Иконки heroicons outline как SVG-path константы в `<script setup>` + рендер `<svg><path :d="item.icon"/></svg>` перед названием пункта. В референсе каждый пункт имеет иконку.
- Шапка: компактная, `sticky top-0`, `backdrop-blur-xl`, бренд-блок (иконка в `rounded-2xl bg-brand-600` + название продукта + подзаголовок «Admin Panel»), справа — ThemeToggle + логин + «Выйти».
- Поддержка тёмной темы через `dark:` классы (Tailwind) — уже есть, сохранить.

Компонент-папки `apps/frontend/src/components/` сейчас пуста — `ThemeToggle.vue` будет первым.

## Acceptance criteria

- [ ] Создан composable `apps/frontend/src/composables/useBranding.ts`:
  - грузит бренд из публичного эндпоинта `GET /api/branding` (без JWT), возвращает реактивные `title`/`faviconUrl`, применяет к `document.title` и `<link rel="icon">`. Дефолты: `'VibeSetup UI'`, `/favicon.svg` — на случай пустого ответа/ошибки сети (не ронять UI).
  - Singleton на уровне модуля, применяется на старте приложения (`main.ts` или `App.vue` `onMounted`).
- [ ] Добавлен минимальный публичный эндпоинт **`GET /api/branding`** (без отдельного модуля/БД — простой `BrandingController` с `@Public()`/без `JwtAuthGuard`, возвращает `{ title, faviconUrl }` из env `BRAND_TITLE` (дефолт `VibeSetup UI`) и `BRAND_FAVICON_URL` (дефолт `/favicon.svg`). Зарегистрирован в `app.module.ts` (или новом мини-модуле `BrandingModule`).
- [ ] Создан компонент `apps/frontend/src/components/ThemeToggle.vue` — вынесенный переключатель Light/System/Dark + icon-toggle; внутри использует `useTheme`; стилистика `rounded-xl border` сегмент-контрола как в референсе.
- [ ] `AdminLayout.vue` переработан:
  - Шапка `sticky top-0 z-40 border-b backdrop-blur-xl` с бренд-блоком (иконка в `rounded-2xl bg-brand-600` + `title` из `useBranding` + подзаголовок «Admin Panel»).
  - **Горизонтальное** меню ниже бренд-строки: `<nav class="flex gap-2 overflow-x-auto">` с кнопками-пунктами, у каждого — иконка (heroicons outline SVG) + название, активный пункт `bg-brand-600 text-white shadow-sm`, неактивный — `border bg-white text-slate-600 hover:bg-slate-50` (тёмная тема — `dark:` варианты). Скролл по `overflow-x-auto` для длинных списков на мобиле.
  - Справа в шапке: `ThemeToggle`, бейдж логина, кнопка «Выйти» (`useAuth.logout`).
  - `navItems` — из актуальных роутов каркаса (после задачи 02 — только «Пользователи» с иконкой `ICON_USERS`; структура должна быть готова добавлять новые пункты по мере развития).
  - `isActive` — учитывает `startsWith` для вложенных роутов (как в референсе), не только exact.
- [ ] Бренд-блок и `useBranding` применяются также в `PublicView.vue` / `LoginView.vue` шапке (если есть) — единое название продукта во всём UI.
- [ ] Иконки вынесены в константы SVG-path в `<script setup>` (как в референсе), не инлайн-разметкой на каждый пункт.
- [ ] Tailwind-класс `brand-600` определён в `apps/frontend/tailwind.config` (проверить наличие `brand` в palette — в референсе используется). Если нет — добавить `brand: { 50..900 }` (взять из референса `tailwind.config`).
- [ ] `useTheme` остаётся (не ломать); `ThemeToggle` его переиспользует.
- [ ] Адаптив: на `< sm` сегмент-контрол темы скрывается (`hidden sm:flex`), остаётся icon-toggle; меню скроллится по горизонтали; шапка не разъезжается.
- [ ] `npx vue-tsc --noEmit` в `apps/frontend` — чисто. dev-сервер/e2e не запускать.

## Подсказки по реализации

- Источник паттернов: `D:\work\projects\wormsoft\inside\agent-hosted\apps\frontend\src\composables\useBranding.ts`, `components\ThemeToggle.vue`, `layouts\AdminLayout.vue` (только дизайн-элементы, НЕ раскладку сайдбара).
- `tailwind.config` референса — взять палитру `brand` оттуда.
- Иконка `ICON_USERS` (heroicons users) — из референса `AdminLayout.vue` константа.
- Порядок: после задачи 02 (чтобы `navItems` уже не содержал telegram-пункт) и независимо от задачи 03 (БД).
- `BrandingController` — предельно простой (без сервиса/БД/entity), только читает `process.env.BRAND_TITLE`/`BRAND_FAVICON_URL`. Фавикон-URL проксируется как есть (frontend/public или внешний URL).

## Проверка

- `cd apps/frontend && npx vue-tsc --noEmit` — без ошибок.
- `cd apps/frontend && npm run build:frontend` — собирается.
- Визуальная проверка — через `@browser-checker` после старта фронтенда пользователем (не запускать самому): шапка с бренд-блоком, горизонтальное меню с иконкой у «Пользователи», переключатель темы работает, тёмная тема корректна.
## Реализация (2025-01-26)

### Что сделано
- **Бэкенд:** создан `BrandingModule` + `BrandingController` — публичный эндпоинт `GET /api/branding` (без JWT, `@Public()`), возвращает `{ title, faviconUrl }` из env `BRAND_TITLE` (дефолт `VibeSetup UI`) и `BRAND_FAVICON_URL` (дефолт `/favicon.svg`). Зарегистрирован в `app.module.ts`. В `.env` добавлены переменные.
- **Фронтенд:** создан composable `useBranding.ts` — singleton (module-level), грузит `/api/branding` один раз на старте (`main.ts` → `loadBranding()`), применяет к `document.title` и `<link rel="icon">`, дефолты на случай ошибки сети. Реактивные `title`/`faviconUrl` используются в шапках.
- **Фронтенд:** создан компонент `ThemeToggle.vue` — вынесенный из разметки переключатель Light/System/Dark (segmented control `hidden sm:flex` + icon-toggle), переиспользует `useTheme`.
- **Фронтенд:** `AdminLayout.vue` переработан — бренд-блок (иконка `bg-brand-600` + `title` из `useBranding` + подзаголовок «Admin Panel»), горизонтальное меню `<nav class="flex gap-2 overflow-x-auto">` с иконкой (heroicons outline SVG-path константа `ICON_USERS`) + названием, активный пункт `bg-brand-600 text-white shadow-sm`, неактивный — `border bg-white` + `dark:` варианты, `ThemeToggle` + бейдж логина + «Выйти» справа. `isActive` — `startsWith` для вложенных роутов.
- **Фронтенд:** `App.vue`, `PublicView.vue`, `LoginView.vue` — используют `useBranding` (единое название продукта).
- **Tailwind:** палитра `brand` уже присутствует (50/100/500/600/700) и совпадает с референсом — изменений не потребовалось.

### Изменённые файлы
- `apps/backend/src/branding/branding.controller.ts` (новый)
- `apps/backend/src/branding/branding.module.ts` (новый)
- `apps/backend/src/app.module.ts` (импорт BrandingModule)
- `apps/backend/.env` (BRAND_TITLE, BRAND_FAVICON_URL)
- `apps/frontend/src/api/branding.ts` (новый)
- `apps/frontend/src/composables/useBranding.ts` (новый)
- `apps/frontend/src/components/ThemeToggle.vue` (новый)
- `apps/frontend/src/layouts/AdminLayout.vue` (рестайл)
- `apps/frontend/src/App.vue` (useBranding, ThemeToggle)
- `apps/frontend/src/views/PublicView.vue` (useBranding)
- `apps/frontend/src/views/LoginView.vue` (useBranding)
- `apps/frontend/src/main.ts` (loadBranding на старте)

### Как проверено
- `cd apps/backend && npx tsc --noEmit` — чисто (без ошибок).
- `cd apps/frontend && npx vue-tsc --noEmit` — чисто (без ошибок).
- `cd apps/frontend && npm run build` — собирается успешно (97 модулей, 2.45s).
- dev-сервер/e2e не запускались (по правилам AGENTS.md).

### Остаточные риски
- Палитра `brand` не имеет оттенков 200/300/400/800/900 — в коде используются `dark:text-brand-400` и `dark:text-brand-300` (в `LoginView.vue`, перенесено из оригинала). Tailwind просто не сгенерирует эти классы — визуально fallback на унаследованный цвет. Не блокирует. Можно дополнить палитру позже.
- Визуальная проверка (браузер) не проводилась — требуется запуск пользователем + `@browser-checker`.
