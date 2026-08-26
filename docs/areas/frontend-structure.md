# Frontend Structure

## Описание

Vue 3 SPA с Composition API, Tailwind CSS и hash router. Публичная страница (`PublicView`) показывает текущее количество пользователей. Админка: `ManageUsersView` (CRUD пользователей) и `ManageFilesView` (управление файлами в S3). Авторизация через JWT в `localStorage`.

## Ключевые файлы

| Файл | Роль |
|------|------|
| `apps/frontend/src/main.ts` | Vue app creation + router mount |
| `apps/frontend/src/App.vue` | Root component: header with nav + router-view |
| `apps/frontend/src/router/index.ts` | Hash router: public + auth routes |
| `apps/frontend/src/api/auth.ts` | Axios client for auth endpoints |
| `apps/frontend/src/api/users.ts` | Axios client for users endpoints |
| `apps/frontend/src/api/files.ts` | Axios client for files endpoints |
| `apps/frontend/src/views/PublicView.vue` | Public page (user count) |
| `apps/frontend/src/views/LoginView.vue` | Login form |
| `apps/frontend/src/views/admin/ManageUsersView.vue` | Users admin CRUD |
| `apps/frontend/src/views/admin/ManageFilesView.vue` | Файлы: таблица + фильтр + загрузчик + скачать/удалить |
| `apps/frontend/src/layouts/AdminLayout.vue` | Admin layout with nav (Пользователи + Файлы) |
| `apps/frontend/src/composables/useAuth.ts` | Auth state: login/logout/checkAuth |
| `apps/frontend/src/style.css` | Tailwind directives |

## Роуты

| Path | Name | Component | Auth required |
|------|------|-----------|---------------|
| `/` | `home` | `PublicView` | No |
| `/login` | `login` | `LoginView` | No (guest) |
| `/admin` | `admin-users` | `ManageUsersView` (via AdminLayout) | Yes |
| `/admin/files` | `admin-files` | `ManageFilesView` (via AdminLayout) | Yes |

`/admin` редиректит на `admin-users`. Guard `requireAuth` стоит на родителе `/admin`.

## API Clients

### auth.ts

- `login(login, password)` → `{ access_token }`
- `getMe(token)` → `{ id, login }`

### users.ts

- `getUsers()` → `PublicUser[]`
- `createUser(data)` → `PublicUser`
- `updateUser(id, data)` → `PublicUser`
- `deleteUser(id)` → `void`
- `getUserCount()` → `{ total, adminCount }` (public, no auth)

### files.ts

- `listFiles({ search?, limit?, offset? })` → `{ items: FileItem[], total }`
- `deleteFile(fileKey)` → `void` (`DELETE /api/files?fileKey=`)
- `uploadFile(file, onProgress?)` → `{ fileKey, fileId }` (multipart `file`)
- `getFileDownloadUrl(fileKey, disposition?)` → presigned GET URL (`GET /api/files/presigned-url`)

`FileItem`: `{ id, fileKey, originalName, size, contentType, inStorage, userId, createdAt, updatedAt }`

## Auth Flow

1. User enters credentials → `POST /api/auth/login`
2. Token saved to `localStorage('auth_token')`
3. `useAuth()` composable provides: `token`, `user`, `login()`, `logout()`, `checkAuth()`
4. Axios interceptor attaches `Authorization: Bearer <token>` automatically
5. Route guard redirects unauthenticated users to `/login`

## Common issues

1. **Hash router**: URLs use `#` (e.g. `http://localhost:5173/#/admin`)
2. **Token not attached**: check axios interceptor in `api/auth.ts`
3. **401 on protected routes**: token expired (24h), re-login