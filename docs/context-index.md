# Context Index

| Файл | Область | Когда использовать |
|------|---------|-------------------|
| `GETTING_STARTED.md` | Запуск с нуля | Новому разработчику/агенту для старта |
| `project-overview.md` | Общая архитектура | Понимание стека и структуры |
| `deployment.md` | Docker, порты, env | Деплой (deploy.sh, GitLab CI: build → deploy:test/production, секреты SOPS+age), контейнеризация, конфиги |
| `agents.md` | Сводка для субагентов | Быстрая навигация и правила |
| `areas/backend-api-structure.md` | Backend API (auth, users, files) | CRUD пользователей, JWT auth, S3-файлы |
| `areas/auth-structure.md` | Аутентификация | JWT, login/logout, guard |
| `areas/database-structure.md` | База данных | TypeORM сущности (User, File), миграции |
| `areas/frontend-structure.md` | Frontend (Nuxt 3 SSR) | Роутинг (history), useApi (SSR), cookie-auth, страницы |
| `areas/nuxt-migration.md` | Гайд миграции на Nuxt | Перенос Vite SPA → Nuxt 3 SSR (референс для форков) |
| `areas/e2e-testing-structure.md` | E2E-тесты | Playwright, headless/CDP, новые тесты |
| `areas/admin-panel.md` | Админ-панель | AdminLayout, ManageUsers + ManageFiles, навигация |
| `migrations.md` | Миграции БД | Режимы, npm-скрипты, baseline + AddFileEntity |
| `testing-guide.md` | Руководство по тестированию | Запуск тестов, написание, проблемы |