# CI-деплой (GitLab CI)

## Деплой через GitLab CI (автоматический)

Пайплайн [`.gitlab-ci.yml`](../../.gitlab-ci.yml): этапы **build → deploy**. На push
в `master` обе джобы `deploy:test` и `deploy:production` запускаются **автоматом**
(перевести прод в manual — правка одной строки `when` в rules джобы).

- **`build:docker`** — собирает и пушит оба образа в Registry
  (`$CI_REGISTRY_IMAGE/{frontend,backend}`) с двумя тегами: `$CI_COMMIT_SHORT_SHA`
  (иммутабельный, именно его пуллят джобы деплоя) + `$CI_COMMIT_REF_SLUG`
  (движущийся тег текущей ветки). Тег `latest` НЕ создаётся.
- **`build:ci-image`** — собирает и пушит образ `$CI_REGISTRY_IMAGE/ci-deploy:latest`
  из `docker/Dockerfile.ci-deploy`. Запускается вручную (`when: manual`) и
  автоматически при изменении `docker/Dockerfile.ci-deploy`.
- **`deploy:test` / `deploy:production`** — деплой из Registry **без сборки на
  сервере**: каждая джоба экспортирует per-стенд age-ключ (`SOPS_AGE_KEY_TEST` /
  `SOPS_AGE_KEY_PRODUCTION` → `SOPS_AGE_KEY`), `DEPLOY_ENV` и запускает
  [`docker/deploy_ci.sh`](../../docker/deploy_ci.sh). `resource_group` на каждой
  джобе защищает от параллельных деплоев одного окружения.

Джобы деплоя используют образ `$CI_REGISTRY_IMAGE/ci-deploy:latest` (а не голый
`ubuntu:24.04`) — sops/yq/ssh уже внутри. `deploy:test` запускается на push
в default-ветку **и в `develop`**.

## Шифрование энвов (SOPS + age)

Секреты окружений хранятся **зашифрованными прямо в git** — механика SOPS + age
(как в ai-provider). В GitLab Variables лежит ТОЛЬКО ключ расшифровки.

> Портабельное описание этой механики (для переноса в другой проект/форк):
> [`../migration_env_crypt.md`](../migration_env_crypt.md) — структура, полные
> исходники скриптов, снипеты интеграции, чеклист.

Структура `.envs/`:

```
.envs/
├── test/
│   ├── public.yaml        # несекретное: SSH_HOST, DOMAIN, PROJECT_NAME, BRAND_*, ...
│   ├── secret.yaml        # секретное (gitignored!): ADMIN_PASSWORD, DEPLOY_SSH_KEY
│   ├── secret.enc.yaml    # зашифрованный secret.yaml (в git)
│   ├── .agekey            # приватный age-ключ стенда (gitignored)
│   └── .agekey.public     # публичный recipient-ключ стенда (в git)
└── production/
    ├── public.yaml
    ├── secret.yaml        # (gitignored)
    ├── secret.enc.yaml
    ├── .agekey            # (gitignored)
    └── .agekey.public
```

- **public.yaml** — несекретные значения (в git открыто);
- **secret.yaml** — секретные значения, **в `.gitignore`**; шаблон — `secret.yaml.example`;
- **secret.enc.yaml** — результат шифрования `secret.yaml` через sops+age, **в git**;
- **`.agekey`** — приватный age-ключ стенда (per-env, **в `.gitignore`** — правило
  матчит `.agekey` на любом уровне);
- **`.agekey.public`** — публичный recipient-ключ стенда (per-env, **в git**) — им
  шифрует `encrypt.sh`.

Переменные окружения в yaml — **ВЕРХНИМ регистром** (`SSH_HOST`, `ADMIN_PASSWORD`,
`DEPLOY_SSH_KEY`), т.к. экспортируются в env. `DEPLOY_SSH_KEY` — `base64` приватного
SSH-ключа деплоя (`base64 -w0 path/to/id_rsa`), без passphrase.

Цикл работы с секретами:

```bash
# 0) Генерация пары ключей для нового стенда (per-env; приватный НЕ коммитить!):
age-keygen -o .envs/test/.agekey        # приватный ключ (gitignored)
age-keygen -y .envs/test/.agekey > .envs/test/.agekey.public   # recipient (в git)
# (альтернатива: grep -o 'age1.*' .envs/test/.agekey > .envs/test/.agekey.public)

# 1) Заполни секреты:
cp .envs/test/secret.yaml.example .envs/test/secret.yaml   # и заполни

# 2) Зашифруй и закоммить результат:
bash scripts/encrypt.sh test     # обновляет .envs/test/secret.enc.yaml
                                 # recipient — из .envs/test/.agekey.public
git add .envs/test/secret.enc.yaml .envs/test/.agekey.public

# 3) Обратно (поредактировать): bash scripts/decrypt.sh test
#    ключ: env SOPS_AGE_KEY > SOPS_AGE_KEY_FILE > .envs/test/.agekey
```

Требуются `sops` и `age-keygen`/`age` ([sops](https://github.com/getsops/sops),
[age](https://github.com/FiloSottile/age)).

## GitLab Variables (Settings → CI/CD → Variables, флаги protected + masked)

| Variable | Окружение |
|----------|-----------|
| `SOPS_AGE_KEY_TEST` | тест-сервер — приватный age-ключ стенда |
| `SOPS_AGE_KEY_PRODUCTION` | прод-сервер — приватный age-ключ стенда |

Каждая переменная — **содержимое приватного age-ключа** стенда (вторая строка
файла `.envs/<env>/.agekey`, начинающаяся с `AGE-SECRET-KEY-`). Ключи
per-стенд: расшифровать тестовые секреты продовым ключом нельзя. При
генерации новой пары для стенда обновите его переменную содержимым нового
`.envs/<env>/.agekey` (остальные переменные не трогаются — ключи env'ов
независимы).

Старые `DEPLOY_BUNDLE_*`, `DEPLOY_HOST` / `DEPLOY_PATH` / `SSH_PRIVATE_KEY` /
`DEPLOY_COMPOSE_PROJECT` больше **не используются**.

## Локальный тест-запуск

```bash
# Ключ — из .envs/<env>/.agekey (per-env, gitignored) или env SOPS_AGE_KEY;
# registry-логин скипается, если CI_REGISTRY/CI_JOB_TOKEN не заданы
# (docker login в registry на сервере сделан руками).
DEPLOY_ENV=test \
FRONTEND_IMAGE="registry.example.com/proj/frontend:abc123" \
BACKEND_IMAGE="registry.example.com/proj/backend:abc123" \
  bash docker/deploy_ci.sh
# Либо всё готовыми значениями: ./deployci-test.sh (DEPLOY_ENV=test по умолчанию;
# проверяет наличие .envs/test/.agekey)
```

## Поток docker/deploy_ci.sh

1. Расшифровывает `.envs/$DEPLOY_ENV/secret.enc.yaml` через `SOPS_AGE_KEY`
   (в CI — из GitLab Variables; при локальном запуске без env — fallback из
   `.envs/$DEPLOY_ENV/.agekey`), мержит с `public.yaml` (yq; secret перекрывает public) и
   экспортирует всё как переменные окружения. Скачивание отсутствующих
   бинарников (`sops`/`yq`) идёт с ретраями (`dl_with_retry`,
   `curl --retry 3`); сначала проверяются предустановленные в `/opt/binaries`
   (несколько форматов путей). Вывод `yq -o p` парсится по формату
   `KEY = value` — с пропуском пустых строк/комментариев и снятием кавычек.
   `DEPLOY_SSH_KEY` (base64) → временный `id_rsa` (chmod 600).
   Затем собирает `ALL_DEPLOY_KEYS` (все ключи merged yq) и в `deploy-env.sh`
   пишет все значения + `EXTRA_ENV_KEYS` (все ключи минус `BASE_DEPLOY_KEYS` —
   generic pass-through: любая переменная форка из
   `.envs/<env>/public.yaml` / `secret.enc.yaml` (ВЕРХНИМ регистром)
   автоматически попадает в `docker/env` без правки деплой-скриптов и
   ansible-шаблонов; в CI задаётся ТОЛЬКО age-ключ).
2. На **пустом** сервере ставит всё с нуля: ansible → docker (роль `deps`) →
   nginx-proxy + acme-companion (роль `proxy`); sftp'ит архив исходников +
   deploy-env.sh (на сервере chmod 600 — содержит пароли/ключи).
3. Генерирует `.app.secrets` (db_password, jwt_secret — один раз, при повторных
   деплоях переиспользуются) и `ansible/vars.yml`.
4. Логин в Registry **временным токеном** (`CI_JOB_TOKEN`, пароль через stdin;
   живёт только в рамках джобы), после деплоя — `docker logout`.
5. Запускает `ansible-playbook` с extra vars `frontend_image`/`backend_image` →
   роль `app` в **Registry-режиме**: прокидывает `FRONTEND_IMAGE`/`BACKEND_IMAGE`
   (теги по SHA) в `docker/.env` и делает `docker compose pull` для слотов (роль
   не делает `up -d` — деплой выполняет `docker/deploy_0downtime.sh --pull`).
   Без этих vars — старый build-режим (ручной `deploy.sh` не менялся).
6. Healthcheck: `https://$DOMAIN/api/users/count` → 200.

## Требования и ограничения CI-деплоя

- **Age-ключ не задан → деплой пропускается**: джоба завершается успешно с
  warning'ом в консоли («деплой пропущен»), пайплайн остаётся зелёным. Чтобы деплой
  заработал — заведите `SOPS_AGE_KEY_*` в Settings → CI/CD → Variables
  (protected+masked).
- Ветка `master` — **protected**: иначе protected-переменные недоступны и джоба
  пропустит деплой (а не упадёт) — ключ просто не будет виден на непротектед ветке.
- **Host key сервера**: по умолчанию `StrictHostKeyChecking=accept-new` — если сервер
  пересоздан и в known_hosts раннера остался старый ключ, деплой упадёт с
  `REMOTE HOST IDENTIFICATION HAS CHANGED`. Отключить проверку — переменная
  `DEPLOY_SKIP_HOST_KEY_CHECK=1` (Settings → CI/CD → Variables; НЕБЕЗОПАСНО — MITM-риск);
  безопасная альтернатива — `ssh-keygen -R <host>` на раннере.
- `CI_JOB_TOKEN` открывает только Registry **своего** проекта; для образов из
  чужого проекта нужен deploy token.
- Чек-лист: оба образа в Registry (тег SHA) → age-ключи заведены (protected+masked,
  ветка protected) → секреты зашифрованы и закоммичены (`.envs/*/secret.enc.yaml`) →
  DNS домена указывает на IP сервера → джобы зелёные →
  `curl https://<DOMAIN>/api/users/count` → 200.

## Отслеживание окончания деплоя по маркеру

Оба скрипта деплоя в самом конце печатают маркер окончания (trap на EXIT —
печатается всегда, и при успехе, и при провале):

| Маркер | Значение |
|---|---|
| `### DEPLOY-FINISHED: ... (exit 0) ###` | деплой завершился успешно |
| `### DEPLOY-FAILED: ... (exit N) ###` | деплой завершился с ошибкой |

Маркер попадает и в stdout, и в лог-файл (`logs/deploy.log` / `logs/deploy-ci.log`).
Это позволяет не следить за логом бесконечно, а дождаться появления маркера.

Примеры ожидания маркера в локальном логе:

```bash
# 1) Ждать маркер в реальном времени (Ctrl+C после появления — tail сам не выйдет,
#    маркер печатается ПЕРЕД завершением скрипта):
tail -f logs/deploy.log

# 2) Однократная проверка «деплой ещё идёт или уже закончился?» по последнему запуску:
grep -E 'DEPLOY-(FINISHED|FAILED)' logs/deploy.log | tail -1

# 3) Запустить деплой и автоматически вернуться, когда появится маркер:
./deploy.sh 2>&1 | sed -n '/### DEPLOY-/q;p'
```

Для CI-деплоя аналогично: маркер `### DEPLOY-FINISHED ###` в конце лога джобы
GitLab означает, что деплой дошёл до конца; `### DEPLOY-FAILED ###` — джоба
упадёт (exit code ≠ 0). Ожидать окончания можно также по статусу pipeline
(`success` / `failed` у джобы `deploy:test` / `deploy:production`).

Частые CI-ошибки:

1. **Deploy-джоба зелёная, но деплой пропущен (warning в логе)** — age-ключ
   (`SOPS_AGE_KEY_TEST` / `SOPS_AGE_KEY_PRODUCTION`) не заведён в
   Settings → CI/CD → Variables, или ветка не protected (protected-переменные
   недоступны на обычных ветках). Заведите ключ — и деплой включится
   на следующем пайплайне.
2. **`docker pull` 401/unauthorized на сервере** — Registry-логин не выполнен:
   при ручном тест-запуске `deploy_ci.sh` без `CI_REGISTRY`/`CI_JOB_TOKEN`
   авторизуйтесь в registry на сервере руками (`docker login`).
