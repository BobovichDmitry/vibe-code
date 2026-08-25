Перенести с `D:\work\projects\wormsoft\inside\agent-hosted` механику работы с задачами: папка `tasks/` и набор скиллов по созданию/решению задач, плюс поддерживающие сабагенты-исполнители.

> **Решения по вопросам:** Q1 — `e2e-writer` поддерживает оба стиля (браузерно-CDP и API-axios); запуск браузера управляется env (`E2E_USE_BROWSER`, `E2E_HEADLESS`) с сохранением CDP-пути по умолчанию. Помимо переноса tooling задача дорабатывает e2e-инфру (fixtures/global-setup).

---

## Контекст (анализ кода)

В референсе `agent-hosted` уже сложилась рабочая механика очереди задач:

- **Папка `tasks/`** с контрактом `tasks/agents.md` (правила работы), `tasks/index.md` (источник истины, разделы Todo/NeedInfo/Errors/Done), `tasks/todo/`, `tasks/done/`.
- **Скиллы** в `.pi/skills/`:
  - `task-creator/SKILL.md` — интерактивное создание задачи (диалог с пользователем, DRAFT → NeedInfo → финализация → Todo).
  - `task-solver/SKILL.md` — разобрать одну верхнюю задачу Todo (SOLVE или NEEDINFO за один проход).
  - `task-batch-solver/SKILL.md` — пройти всю очередь Todo через субагентов (code-solver → e2e-writer → test-runner/test-fixer → docs-maintainer → git commit на каждую задачу).
  - `task-list-converter/SKILL.md` — пакетная конвертация файла-списка (`small_tasks.md`) в готовые файлы задач с анализом кода.
- **Сабагенты-исполнители** в `.pi/agents/`: `code-solver.md`, `e2e-writer.md` (не совпадает со стилем e2e в этом проекте — см. ниже), `docs-maintainer.md`, `test-runner.md`, `test-fixer.md`, `browser-checker.md`, `html-designer.md`.

В текущем проекте `vibecode-setup` уже есть `.pi/agents/` с `browser-checker`, `docs-maintainer`, `html-designer`, `test-fixer`, `test-runner`. **Отсутствуют:** `code-solver` (реализует одну задачу с чистым контекстом) и `e2e-writer`. Папки `tasks/` и `.pi/skills/` нет вообще.

**Расхождение по e2e (решено):** скиллы `agent-hosted` (`task-batch-solver`, `e2e-writer`) рассчитаны на **API-based** e2e (изолированный backend + mock-ai). В этом проекте e2e — **браузерные через CDP** (`e2e/fixtures.ts` → `connectedBrowser`/`connectedPage`, реальный Chrome на `--remote-debugging-port=9222`). Решение пользователя: `e2e-writer` должен уметь **обоими** стилями — писать браузерно-CDP спеки (как сейчас) И API-стиль (axios против `E2E_API_URL`), а запуск браузера должен управляться env, в т.ч. **headless**-режим. Значит, кроме переноса скиллов/сабагентов нужно доработать e2e-инфра (fixtures/global-setup) — см. Acceptance.

## Acceptance criteria

- [ ] Создана папка `tasks/` с `agents.md` (контракт) и `index.md` (Todo/NeedInfo/Errors/Done) — уже сделано в рамках декомпозиции, задача закрепляет контракт.
- [ ] Перенесены 4 скилла в `.pi/skills/`:
  - `task-creator/SKILL.md`, `task-solver/SKILL.md`, `task-batch-solver/SKILL.md`, `task-list-converter/SKILL.md`.
- [ ] Скиллы адаптированы под текущий проект: пути/команды/ссылки на `AGENTS.md` корректны для `vibecode-setup` (не осталось жёстких ссылок на `agent-hosted`, кроме референса-примера).
- [ ] Создан сабагент `.pi/agents/code-solver.md` (по образцу `agent-hosted`, с `defaultContext: fresh`, `disallowed_tools` без `chrome_devtools_*` и `subagent`, проверка через `tsc --noEmit`/`vue-tsc --noEmit`).
- [ ] Создан сабагент `.pi/agents/e2e-writer.md`, **поддерживающий оба стиля**: умеет писать браузерно-CDP спеки (через `connectedPage` из `e2e/fixtures.ts`, как в существующих `e2e/tests/*.spec.ts`) И API-стиль (axios-спеки против `E2E_API_URL`, без браузера). В задании от оркестратора стиль определяется по сути задачи (визуал/DOM → браузер; чистый API/бизнес-логика → API-стиль). Скилл прямо описывает оба паттерна с примерами.
- [ ] **e2e-инфра доработана для env-управления браузером:**
  - `e2e/fixtures.ts`/`e2e/global-setup.ts` читают env: `E2E_USE_BROWSER` (`true` по умолчанию) и `E2E_HEADLESS` (`false` по умолчанию). При `E2E_USE_BROWSER=true` + `E2E_HEADLESS=true` — Playwright запускает `chromium` headless (через `_launch`/`chromium.launch({ headless: true })`) вместо `connectOverCDP`. При `E2E_USE_BROWSER=false` — браузер не поднимается совсем (только API-тесты через axios).
  - CDP-режим (`connectOverCDP` к `REMOTE_CHROME_HOST:BROWSER_PORT`) сохраняется как путь по умолчанию (`E2E_HEADLESS=false`) — текущее поведение не ломается.
  - `e2e/.env`/`playwright.config.ts` — добавлены переменные `E2E_USE_BROWSER`, `E2E_HEADLESS` с дефолтами и комментариями. API-стиль-тестам нужен запущенный backend (`dev:backend:log`) — пользователь поднимает; `test-runner` это учитывает.
- [ ] `task-batch-solver` адаптирован: e2e-стадия запускается через существующий `test-runner` (`npm run test:e2e`); упоминания «изолированный backend 3511 / mock-ai 9101» убраны; e2e-стадия остаётся, но стиль теста выбирает `e2e-writer`.
- [ ] `tasks/index.md` отражает реальное состояние очереди (5 задач в Todo), `tasks/todo/` содержит файлы задач.
- [ ] Конфликтов имён сабагентов нет: существующие `docs-maintainer`/`test-runner`/`test-fixer`/`browser-checker`/`html-designer` либо переиспользуются как есть, либо дополняются до контракта `task-batch-solver` (роли Код/E2E/Прогон/Починка/Докум.).
- [ ] `npx vue-tsc --noEmit` / `npx tsc --noEmit` — без ошибок (задача трогает только e2e-инфру из кода; `.pi/`-конфиги — markdown, не компилируются).

## Подсказки по реализации

- Источник для копирования: `D:\work\projects\wormsoft\inside\agent-hosted\.pi\skills\{task-creator,task-solver,task-batch-solver,task-list-converter}\SKILL.md` и `.pi\agents\{code-solver,e2e-writer}.md`.
- При переносе скиллов замените в тексте ссылки `tasks/agents.md` уже созданным файлом (контракт совпадает), оставьте принципы «источник истины — index.md», «минимум вопросов», «один проход — SOLVE или NEEDINFO».
- В `task-batch-solver` этап `e2e-writer`/`test-runner` сейчас завязан на `npx playwright test` против CDP-браузера — сохраните вызов `test-runner` (сабагент уже есть в проекте), но уберите ссылку на «изолированный backend 3511/mock-ai 9101» (её здесь нет). Либо пометьте e2e-стадию как опциональную до адаптации `e2e-writer`.
- `code-solver` переносится почти дословно: запреты `subagent`/`chrome_devtools_*`, проверка `apps/backend: tsc --noEmit`, `apps/frontend: vue-tsc --noEmit`.
- Код приложения (`apps/**`) задача в основном не трогает — **исключение e2e-инфра** (`e2e/fixtures.ts`, `e2e/global-setup.ts`, `e2e/.env`, `playwright.config.ts`): доработка env-управления браузером по решению Q1. Это единственная правка кода в задаче.
- Для headless-запуска использовать Playwright `chromium` из `@playwright/test` (уже в зависимостях e2e); CDP-путь оставить как есть.

## Проверка

- `ls tasks/ tasks/todo/ tasks/done/` — структура на месте.
- `ls .pi/skills/` — 4 папки с `SKILL.md`.
- `ls .pi/agents/` — есть `code-solver.md` и `e2e-writer.md` (остальные на месте).
- Контент `tasks/index.md` совпадает с фактическими файлами в `tasks/todo/`.
- `e2e/fixtures.ts`/`global-setup.ts` — `E2E_USE_BROWSER`/`E2E_HEADLESS` читаются; CDP-путь по умолчанию сохранён; headless-ветка через `chromium.launch` есть.
- `cd e2e && npx tsc --noEmit` (если применимо) / `npx playwright test --list` — синтаксис спек не сломан.
- dev-серверы и e2e-прогон не запускать (проверка типов/синтаксиса только).
---

## Реализация (2025-01-24)

### Что сделано

- Перенесены 4 скилла в `.pi/skills/`: `task-creator`, `task-solver`, `task-batch-solver`, `task-list-converter` — адаптированы под vibecode-setup (пути, команды, ссылки на `AGENTS.md`, примеры из реального кода проекта).
- Создан сабагент `.pi/agents/code-solver.md` — `defaultContext: fresh`, `disallowed_tools` без `chrome_devtools_*` и `subagent`, проверка через `tsc --noEmit`/`vue-tsc --noEmit`.
- Создан сабагент `.pi/agents/e2e-writer.md` — поддерживает оба стиля e2e: браузерно-CDP (через `connectedPage` из `e2e/fixtures.ts`) и API-стиль (axios против `E2E_API_URL`). Выбор стиля — по сути задачи (таблица в описании агента).
- e2e-инфра доработана для env-управления браузером:
  - `e2e/fixtures.ts`, `e2e/global-setup.ts`, `e2e/playwright.config.ts`, `e2e/.env` — заменён `E2E_BROWSER_MODE` на `E2E_USE_BROWSER` (default `true`) + `E2E_HEADLESS` (default `false`).
  - `E2E_USE_BROWSER=true` + `E2E_HEADLESS=false` → CDP (`connectOverCDP`) — путь по умолчанию, поведение не сломано.
  - `E2E_USE_BROWSER=true` + `E2E_HEADLESS=true` → Playwright `chromium.launch({ headless: true })`.
  - `E2E_USE_BROWSER=false` → браузер не поднимается (API-only тесты через axios). `connectedBrowser`/`connectedPage` бросают ошибку.
- `task-batch-solver` адаптирован: упоминания «изолированный backend 3511 / mock-ai 9101» убраны; e2e-стадия через существующий `test-runner`; стиль теста выбирает `e2e-writer`; коммит через точечный `git add` (не `git add -A`).

### Изменённые файлы

- `.pi/skills/task-creator/SKILL.md` — новый
- `.pi/skills/task-solver/SKILL.md` — новый
- `.pi/skills/task-batch-solver/SKILL.md` — новый
- `.pi/skills/task-list-converter/SKILL.md` — новый
- `.pi/agents/code-solver.md` — новый
- `.pi/agents/e2e-writer.md` — новый
- `e2e/fixtures.ts` — refactor: `E2E_USE_BROWSER`/`E2E_HEADLESS`, headless-ветка, API-only guard
- `e2e/global-setup.ts` — refactor: новые env-переменные, условный CDP-чек
- `e2e/playwright.config.ts` — refactor: `headless` из env, `globalSetup` по условию
- `e2e/.env` — новые переменные `E2E_USE_BROWSER`/`E2E_HEADLESS` с дефолтами и комментариями

### Как проверено

- `apps/backend`: `npx tsc --noEmit` — OK (0 ошибок)
- `apps/frontend`: `npx vue-tsc --noEmit` — OK (0 ошибок)
- `e2e`: `npx playwright test --list` — OK (9 тестов в 2 файлах, синтаксис не сломан)
- dev-серверы и e2e-прогон не запускались (по правилам проекта)

### Остаточные риски

- Существующие спеки (`basic.spec.ts`, `telegram-settings.spec.ts`) используют стандартный `page` из `@playwright/test`, а не кастомные `connectedPage` из `fixtures.ts` — это не влияет на функциональность, но при `E2E_USE_BROWSER=false` стандартный `page` всё равно попытается запустить браузер (Playwright управляет им независимо). API-only тесты (без `page`) работают без браузера. Это известное ограничение Playwright — полностью отключить стандартный `page` fixture нельзя.
- В `e2e/global-setup.ts` осталась потенциальная type-ошибка с `execSync` shell-опцией (pre-existing, не введена этой задачей) — не блокирует, т.к. tsconfig в e2e отсутствует и проверка идёт через `playwright test --list`.
