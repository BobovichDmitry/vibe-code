# Admin Panel

## Описание

Защищённая маршрутами часть приложения. `AdminLayout` с **левым вертикальным сайдбаром** (по образцу agent-hosted): бренд-блок сверху, вертикальная навигация, внизу — `ThemeToggle`, бейдж логина и кнопка «Выйти». На `< lg` сайдбар открывается бургером как overlay-drawer. Две страницы: `ManageUsersView` (CRUD пользователей) и `ManageFilesView` (управление файлами в S3).

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/frontend/src/layouts/AdminLayout.vue` | Admin layout с вертикальным сайдбаром (nav + ThemeToggle + logout) |
| `apps/frontend/src/components/ThemeToggle.vue` | Переключатель темы Light/System/Dark |
| `apps/frontend/src/composables/useBranding.ts` | Название продукта/favicon (бренд-блок сайдбара) |
| `apps/frontend/src/views/admin/ManageUsersView.vue` | Users CRUD table |
| `apps/frontend/src/views/admin/ManageFilesView.vue` | Файлы: таблица + фильтр/пагинация + загрузчик + скачать/удалить |
| `apps/frontend/src/api/files.ts` | API-клиент файлов (list/delete/upload/download URL) |

## Маршруты

| Path | Name | Component |
|------|------|-----------|
| `/admin` | `admin-users` | ManageUsersView (редирект с `/admin`) |
| `/admin/files` | `admin-files` | ManageFilesView |

Оба — дочерние к `/admin` (родитель — `AdminLayout`). Guard `requireAuth` стоит на родителе.

## Навигация

Сайдбар `AdminLayout.vue` содержит пункты «Пользователи» (`/admin`) и «Файлы» (`/admin/files`, иконка `ICON_FILES`). Активный пункт определяется **точным совпадением** пути (`route.path === path`) — каждая страница лист-роут.

## Guard

Route guard в `router/index.ts` проверяет `localStorage.getItem('auth_token')`. Без токена — redirect на `/login`.

## ManageFilesView

- Таблица файлов из S3 с фильтром по `fileKey` (подстрока, case-insensitive, дебаунс) и пагинацией (`limit`/`offset`).
- Тестовый загрузчик: drag-and-drop + клик → `POST /api/files` (multipart `file`, рандомное имя на бэке), прогресс-бар.
- Действия: скачать (presigned GET URL, открывается в новой вкладке), удалить (`DELETE /api/files?fileKey=`).

## Common issues

1. **Admin button not visible**: not authenticated, check `localStorage`
2. **Redirect loop**: token expired but router guard didn't clear it
3. **Файлы не загружаются**: S3 не настроен — проверьте `S3_*` env (см. `docs/areas/backend-api-structure.md`)
4. **404 при скачивании**: объект отсутствует в S3, но запись в БД есть (`inStorage=false`) — вызовите `update-meta` или удалите запись
