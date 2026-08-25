# Admin Panel

## Описание

Защищённая маршрутами часть приложения. `AdminLayout` с **левым вертикальным сайдбаром** (по образцу agent-hosted): бренд-блок сверху, вертикальная навигация, внизу — `ThemeToggle`, бейдж логина и кнопка «Выйти». На `< lg` сайдбар открывается бургером как overlay-drawer. `ManageUsersView` — CRUD пользователей.

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/frontend/src/layouts/AdminLayout.vue` | Admin layout с вертикальным сайдбаром (nav + ThemeToggle + logout) |
| `apps/frontend/src/components/ThemeToggle.vue` | Переключатель темы Light/System/Dark |
| `apps/frontend/src/composables/useBranding.ts` | Название продукта/favicon (бренд-блок сайдбара) |
| `apps/frontend/src/views/admin/ManageUsersView.vue` | Users CRUD table |

## Маршруты

| Path | Component |
|------|-----------|
| `/admin` | ManageUsersView |

## Guard

Route guard в `router/index.ts` проверяет `localStorage.getItem('auth_token')`. Без токена — redirect на `/login`.

## Common issues

1. **Admin button not visible**: not authenticated, check `localStorage`
2. **Redirect loop**: token expired but router guard didn't clear it
