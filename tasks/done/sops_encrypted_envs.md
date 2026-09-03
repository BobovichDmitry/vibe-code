# Переработать деплой: шифрование энвов в git (SOPS + age, как в ai-provider)

Переработать деплой: перейти на механику шифрования энвов как в `ai-provider` (`D:\work\projects\wormsoft\inside\ai-provider`). Ключ расшифровки хранится в GitLab Variables, секреты (включая base64 приватного ключа деплоя) хранятся в зашифрованном виде прямо в git; переменные окружения подставляются при запуске docker.

---

## Контекст (анализ кода)

### Референс (ai-provider)

- `.envs/<env>/secret.yaml` (открытый, в gitignore) → `sops --encrypt --age` → `.envs/<env>/secret.enc.yaml` (в git). `.envs/<env>/public.yaml` — несекретные значения, открыто.
- `.agekey` (private age key, НЕ в git) / `.agekey.public` (recipient, в git). Скрипты `scripts/encrypt.sh <env>` / `scripts/decrypt.sh <env>` — цикл «поредактировал открытый файл → зашифровал → закоммитил».
- На сервере `scripts/run.sh` расшифровывает `secret.enc.yaml` через `SOPS_AGE_KEY`, мёржит с `public.yaml` через `yq` и экспортирует всё как env → `docker compose`.

### Текущее состояние проекта

- **`.gitlab-ci.yml`**: stages build → deploy. `deploy:test` / `deploy:production` берут `DEPLOY_BUNDLE_TEST` / `DEPLOY_BUNDLE_PRODUCTION` (base64(tar.gz[id_rsa, .env])) из GitLab Variables → `bash docker/deploy_ci.sh`.
- **`docker/deploy_ci.sh`** (325 строк): распаковывает бандл (`id_rsa` + `.env` с `SSH_HOST, SSH_USER, SSH_PORT, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD, PROJECT_NAME, BRAND_*, ...`) → SSH на сервер → установка ansible → архив исходников + `deploy-env.sh` → генерация `.app.secrets` (db_password, jwt_secret — раз, на сервере) и `ansible/vars.yml` → `ansible-playbook` (pull образов из Registry, без сборки) → healthcheck.
- **`deploy.sh`** — ручной деплой, работает с `SSH_KEY`/env напрямую, механику бандла не использует.
- **`scripts/make_deploy_bundle.sh` / `decode-bundle.sh` / `.ci-bundle`** — инструменты старой схемы, станут неактуальны.

### Что меняется / не меняется

- **НЕ меняется**: пайплайн (build в Registry → `deploy_ci.sh` → pull образов), ansible-плейбук, `docker-compose.prod.yml`, генерация `.app.secrets` на сервере.
- **Меняется**: источник секретов для `deploy_ci.sh` — вместо base64-бандла `DEPLOY_BUNDLE_*` из GitLab Variables → SOPS-зашифрованные `.envs/<env>/secret.enc.yaml` в git. В GitLab Variables остаётся ТОЛЬКО age-ключ: `SOPS_AGE_KEY_TEST`, `SOPS_AGE_KEY_PRODUCTION` — в `.gitlab-ci.yml` каждой джобы явно указано, какую переменную брать для расшифровки (per-стенд ключи, легко добавить новые).

## Acceptance criteria

1. **Структура `.envs/`** как в ai-provider:
   - `.envs/test/public.yaml` — несекретное: `SSH_HOST, SSH_USER, SSH_PORT, DOMAIN, LETSENCRYPT_EMAIL, PROJECT_NAME, PROJECT_DIR?, PROXY_DIR?, BRAND_TITLE, BRAND_FAVICON_URL, ADMIN_LOGIN`.
   - `.envs/test/secret.yaml` (gitignored!) — секретное: `ADMIN_PASSWORD`, `DEPLOY_SSH_KEY` (base64 приватного ключа деплоя, `id_rsa`).
   - Аналогично `.envs/production/...`.
   - `.envs/*/secret.enc.yaml` — зашифрованные sops+age, лежат в git.
2. **Скрипты шифрования** `scripts/encrypt.sh <env>` и `scripts/decrypt.sh <env>` — как в ai-provider (recipient из `.agekey.public`, ключ из `.agekey` или env `SOPS_AGE_KEY`). `.agekey` — в `.gitignore` (рядом с `.ci-bundle`).
3. **`.gitlab-ci.yml`**: джобы `deploy:test` / `deploy:production` больше не проверяют/используют `DEPLOY_BUNDLE_*`. Вместо этого явно: `deploy:test` → `export SOPS_AGE_KEY="$SOPS_AGE_KEY_TEST" DEPLOY_ENV=test`; `deploy:production` → `export SOPS_AGE_KEY="$SOPS_AGE_KEY_PRODUCTION" DEPLOY_ENV=production` — и обе запускают `bash docker/deploy_ci.sh`. Если `SOPS_AGE_KEY_*` не задан — деплой ПРОПУСКАЕТСЯ с warning (как сейчас), джоба зелёная.
4. **`deploy_ci.sh`**: вместо распаковки бандла:
   - читает `DEPLOY_ENV` (test|production), расшифровывает `.envs/$DEPLOY_ENV/secret.enc.yaml` через `SOPS_AGE_KEY` (или читает `.agekey` при локальном запуске), мёржит с `.envs/$DEPLOY_ENV/public.yaml` (yq) и экспортирует как env;
   - `id_rsa` пишет из `DEPLOY_SSH_KEY` (base64 -d) во временный файл с chmod 600;
   - остальной поток (ansible, Registry, healthcheck) — без изменений.
5. **CI-образ джобы** (`ubuntu:24.04`) — доустановить sops и yq (бинарники через curl или apt) в `before_script` / начала скрипта `deploy_ci.sh` (локально на shell-раннере — скип, если уже есть).
6. **Локальный запуск**: `DEPLOY_ENV=test SOPS_AGE_KEY="$(cat .agekey)" ... bash docker/deploy_ci.sh` работает без GitLab Variables.
7. **Уборка**: `scripts/make_deploy_bundle.sh`, `scripts/decode-bundle.sh`, упоминания `DEPLOY_BUNDLE_*` и `.ci-bundle` убраны; `.gitlab-ci.yml`-комментарии в шапке обновлены (`SOPS_AGE_KEY_TEST/PRODUCTION` вместо бандлов).
8. **Документация**: обновлены `docker/deploy_ci.sh` (шапка), `docs/deployment.md` — описание `.envs/`, цикла encrypt/decrypt, новых GitLab Variables, per-env ключей.

## Подсказки по реализации

- Референс-файлы: `.gitlab-ci.yml`, `scripts/{run,encrypt,decrypt}.sh`, `.envs/` — `D:\work\projects\wormsoft\inside\ai-provider`.
- Утилита мержа в ai-provider: `yq ea -o p '. as $item ireduce ({}; . * $item)'` — значения secret перекрывают public; `awk '{gsub(/\./,"_",$1)}{print toupper($1)$2$3}'` → верхний регистр. У нас compose/ansible ждут ВЕРХНИЙ регистр (`SSH_HOST`, `ADMIN_PASSWORD`) — проверить маппинг и, при расхождении, писать keys уже в верхнем регистре.
- `yq` из apt (`debian`-репо, `yq` = python-вариант, НЕ тот) — лучше качать официальный бинарник `mikefarah/yq` (v4). SOPS — официальный бинарник `getsops/sops`.
- `deploy_ci.sh` уже экспортирует `.env` через `set -a; source` — заменить на расширенные переменные из расшифровки; контракты (`: "${SSH_HOST:?...}"` и т.д.) оставить как есть.
- `.gitignore`: `.envs/*/secret.yaml`, `.agekey` (по аналогии с текущими `.env.local`/`.ci-bundle` правилами).
- Передача `SOPS_AGE_KEY` в `deploy_ci.sh` — только через переменную окружения джобы (не через argv/файл), чтобы не светился в логах; в CI-переменных включить masked.
- Свежий `secret.enc.yaml` для каждого стенда сгенерировать: создать `.agekey`/`.agekey.public`, `.envs/<env>/secret.yaml`, прогнать `scripts/encrypt.sh <env>` — коммитит пользователь сам (или пустые `.enc.yaml`-заготовки + инструкция в docs).

## Проверка

- `bash -n scripts/encrypt.sh scripts/decrypt.sh docker/deploy_ci.sh` — синтаксис ок.
- Локальный smoke: `DEPLOY_ENV=test SOPS_AGE_KEY="$(...)" bash docker/deploy_ci.sh` с «ненастоящими» образами — упадёт на SSH, но успеет расшифровать энвы (проверить: ключ создан, переменные экспортированы).
- `yq`/`sops` доступны в CI-образе: руками проверить установку (если это можно проверить без деплоя).
- dev-серверы и e2e не запускать (по правилам проекта).

---

## Реализация (2026-09-09)

- **`.envs/`**: `test/` + `production/`: `public.yaml` (открытые значения), `secret.yaml.example` (шаблон секретов; `secret.yaml` gitignored). Ключи yaml — ВЕРХНИМ регистром (экспортируются в env). `DEPLOY_SSH_KEY` = base64 приватного ключа деплоя. Зашифрованные `secret.enc.yaml` НЕ сгенерированы (нет age-ключа/`sops` локально) — генерируются пользователем: `age-keygen -o .agekey` → `scripts/encrypt.sh <env>` (инструкция в docs/deployment.md).
- **`scripts/encrypt.sh` / `scripts/decrypt.sh`** — новые, механика как в ai-provider: recipient из `.agekey.public`, ключ из env `SOPS_AGE_KEY`/`SOPS_AGE_KEY_FILE`/`./.agekey`.
- **`docker/deploy_ci.sh`**:
  - шапка переписана (SOPS вместо бандла);
  - секция «распаковка бандла» заменена на: `DEPLOY_ENV` контракт → `ensure_sops_yq()` (авто-установка официальных бинарников sops v3.9.4 и yq v4.47.2 во временный bin-dir, если их нет) → расшифровка `secret.enc.yaml` через sops (ключ через `SOPS_AGE_KEY`/`SOPS_AGE_KEY_FILE`/`.agekey`) → мерж с `public.yaml` через `yq ea` → export строк `KEY=value` в цикле (values с пробелами поддержаны) → `base64 -d` `DEPLOY_SSH_KEY` → временный `id_rsa` (600);
  - fixed: trap EXIT конфликт (`deploy_exit_marker` перетирался вторым `trap`) — cleanup `BUNDLE_DIR` теперь внутри `deploy_exit_marker`;
  - остальной поток (ansible, Registry pull, healthcheck) не тронут.
- **`.gitlab-ci.yml`** — `deploy:test`/`deploy:production` проверяют `SOPS_AGE_KEY_TEST`/`SOPS_AGE_KEY_PRODUCTION`; если нет — скип с warning (зелёная джоба); иначе `export SOPS_AGE_KEY=... DEPLOY_ENV=...` → `bash docker/deploy_ci.sh`. Шапка переписана.
- **`deployci-test.sh`** — переписан под новую механику (ключ из `.agekey`/`SOPS_AGE_KEY` вместо `.ci-bundle`).
- **Уборка**: удалены `scripts/make_deploy_bundle.sh`, `scripts/decode-bundle.sh`; из `.gitignore` убраны `.ci-bundle`, `/scripts/decoded-bundle/`, добавлены `.agekey`, `.envs/*/secret.yaml`.
- **docs/deployment.md** — раздел бандлов переписан: структура `.envs/`, цикл encrypt/decrypt, новые GitLab Variables `SOPS_AGE_KEY_*`, локальный тест-запуск, обновлены «Требования», чек-лист и «Частые ошибки».

Проверено: `bash -n` всех трёх скриптов, YAML-валидация `.gitlab-ci.yml` (js-yaml), smoke-тест пайплайна расшифровка→мерж→export→id_rsa на мок-бинарниках sops/yq (значения с пробелами, base64-ключ — ок).

Риски/TODO:
- `secret.enc.yaml` для обоих стендов нужно сгенерировать пользователем (age-keygen + encrypt.sh) и закоммитить;
- лежащий в корне устаревший `.ci-bundle` (содержит секреты!) можно удалить руками;
- версии sops/yq в `ensure_sops_yq` запинены — при обновлении менять в одном месте.
