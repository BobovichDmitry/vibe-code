# Per-env шифрование секретов (SOPS + age) — механика и миграция

> **Портабельный документ.** Описывает механику per-env шифрования секретов,
> внедрённую в этом проекте, так, чтобы её можно было смержить в любой другой
> проект/форк: структура файлов, полные исходники скриптов, снипеты интеграции,
> GitLab CI и пошаговый чеклист. Ничего кроме этого файла и перечисленных
> снипетов переносить не нужно.
>
> Связанное в этом репо: `docs/areas/ci-deployment.md` (полный поток CI-деплоя),
> `scripts/encrypt.sh` / `scripts/decrypt.sh` (эталонные реализации).

## 1. Идея механики

Секреты стендов (пароли, SSH-ключи деплоя, токены) хранятся в git **зашифрованными**
(SOPS + age), по одной независимой паре ключей **на каждый стенд (env)**:

- **`.envs/<env>/.agekey`** — приватный age-ключ стенда. **НИКОГДА не в git**
  (gitignored). Живёт только: локально у девопера / в GitLab CI Variables.
- **`.envs/<env>/.agekey.public`** — публичный ключ (recipient), **в git**. Нужен
  всем, кто шифрует секреты стенда (`encrypt.sh`).
- **`.envs/<env>/secret.yaml`** — секреты открытым текстом, **gitignored**;
  **`.envs/<env>/secret.enc.yaml`** — зашифрованный результат, **в git**;
  `secret.yaml.example` — шаблон (в git, значения-заглушки).

Ключи per-env = изоляция стендов: утёкший тестовый ключ не даёт расшифровать
прод, и наоборот. Отдельный стенд → отдельная папка `.envs/<env>/` → отдельная
пара ключей, скрипты берут ключ автоматически по имени env — никаких флагов.

```
.envs/
├── test/
│   ├── public.yaml           # открытые значения (в git)
│   ├── secret.yaml.example   # шаблон секретов (в git)
│   ├── secret.yaml           # секреты (gitignored)
│   ├── secret.enc.yaml       # sops+age (в git)
│   ├── .agekey               # приватный ключ test (gitignored)
│   └── .agekey.public        # recipient test (в git)
└── production/
    └── ... (то же самое)
```

Переменные в yaml — **ВЕРХНИМ регистром** (`SSH_HOST`, `ADMIN_PASSWORD`,
`DEPLOY_SSH_KEY`), т.к. дальше экспортируются в env. `DEPLOY_SSH_KEY` — base64
приватного SSH-ключа деплоя (`base64 -w0 path/to/id_rsa`), без passphrase.

## 2. Инструменты

- [`sops`](https://github.com/getsops/sops) — шифрование файлов (yaml);
- [`age`](https://github.com/FiloSottile/age) — только утилита `age-keygen`
  (генерация пары). Проверка: `sops --version`, `age-keygen --version`.

В деплой-скриптах этого проекта есть `ensure_sops_yq` — авто-установка sops/yq
во временный bin-dir, если их нет (см. `docker/deploy_ci.sh`). Для локальной
работы поставь руками (brew/winget/apt) или скопируй `ensure_sops_yq`.

## 3. Установка в новый проект (fresh setup)

### Шаг 1 — структура папок и gitignore

```bash
mkdir -p .envs/test .envs/production
cp <шаблон> .envs/test/secret.yaml.example   # опиши секреты стенда
```

В корневой `.gitignore` добавить (правило `.agekey` без слэша матчится
на **любом уровне** — покрывает и `.envs/<env>/.agekey`):

```gitignore
# CI-деплой: приватные age-ключи (per-env: .envs/<env>/.agekey, правило .agekey —
# на любом уровне) и открытые секреты энвов — НИКОГДА не коммитить.
# Публичные ключи .envs/<env>/.agekey.public — В git (recipient для encrypt.sh).
.agekey
.envs/*/secret.yaml
```

> Проверка: `git check-ignore .envs/test/.agekey` → совпадение;
> `git check-ignore .envs/test/.agekey.public` → пусто (не игнорируется).

### Шаг 2 — пара ключей на КАЖДЫЙ стенд

```bash
# test
age-keygen -o .envs/test/.agekey                                   # приватный (gitignored)
age-keygen -y .envs/test/.agekey > .envs/test/.agekey.public       # публичный → в git
# production — отдельная пара!
age-keygen -o .envs/production/.agekey
age-keygen -y .envs/production/.agekey > .envs/production/.agekey.public

git add .envs/test/.agekey.public .envs/production/.agekey.public
```

> `age-keygen -y <file>` печатает только публичный ключ. Альтернатива:
> `grep -o 'age1.*' .envs/test/.agekey > .envs/test/.agekey.public`.
> **Приватный ключ не коммитить и не вставлять в доки/тикеты.**

### Шаг 3 — скрипты encrypt/decrypt (полные исходники)

Положить в `scripts/encrypt.sh` и `scripts/decrypt.sh` (см. раздел 6),
выдать права: `chmod +x scripts/encrypt.sh scripts/decrypt.sh`.

Цикл работы с секретами:

```bash
cp .envs/test/secret.yaml.example .envs/test/secret.yaml   # и заполнить
bash scripts/encrypt.sh test                               # → secret.enc.yaml
git add .envs/test/secret.enc.yaml

# Обратно (поредактировать): bash scripts/decrypt.sh test
```

### Шаг 4 — интеграция в деплой-скрипты

Деплой-скрипт знает стенд в переменной `DEPLOY_ENV` (test | production | ...).
Перед расшифровкой резолвит ключ автоматически (см. снипеты в разделе 7).
Приоритет: env `SOPS_AGE_KEY` (CI) > `SOPS_AGE_KEY_FILE` > файл `.envs/$DEPLOY_ENV/.agekey`
(локальный запуск без CI).

### Шаг 5 — GitLab CI

В **Settings → CI/CD → Variables** (protected + masked) — по одной переменной
**на каждый стенд**, значение = **содержимое приватного ключа** (вторая строка
`.envs/<env>/.agekey`, начинается с `AGE-SECRET-KEY-`):

| Variable | Что кладём |
|----------|-----------|
| `SOPS_AGE_KEY_TEST` | содержимое `.envs/test/.agekey` |
| `SOPS_AGE_KEY_PRODUCTION` | содержимое `.envs/production/.agekey` |

Джоба деплоя экспортирует и вызывает деплой-скрипт:

```yaml
deploy:production:
  # rules: только default-ветка; resource_group: deploy-production
  script:
    - |
      if [ -z "${SOPS_AGE_KEY_PRODUCTION:-}" ]; then
        echo "⚠ SOPS_AGE_KEY_PRODUCTION не задан — деплой ПРОПУЩЕН."
        exit 0
      fi
      export SOPS_AGE_KEY="$SOPS_AGE_KEY_PRODUCTION"
      export DEPLOY_ENV=production
      export FRONTEND_IMAGE="$FRONTEND_IMAGE_SHA"   # образы по SHA коммита
      export BACKEND_IMAGE="$BACKEND_IMAGE_SHA"
      bash docker/deploy_ci.sh
```

Схема симметрична для `deploy:test` (`SOPS_AGE_KEY_TEST` + `DEPLOY_ENV=test`,
rules на feature/develop-ветку). Отсутствие ключа = деплой молча пропускается
(пайплайн зелёный) — удобно, пока стенд ещё не заведён.

## 4. Миграция со старой механики (один корневой ключ)

Если в проекте уже была механика «одна пара в корне репо» (`.agekey` +
`.agekey.public` в корне, все энвы зашифрованы одним ключом):

1. **Определи, какому стенду принадлежит корневой ключ** — обычно это прод
   (первый настроенный стенд). Проверь, что расшифровка работает:
   `SOPS_AGE_KEY_FILE=./.agekey sops -d .envs/production/secret.enc.yaml`.
2. **Перенеси пару в папку ЭТОГО стенда** (ключ не меняется — уже
   зашифрованные файлы этого стенда остаются валидными, re-encrypt не нужен):
   ```bash
   mv .agekey .envs/production/.agekey
   git mv .agekey.public .envs/production/.agekey.public
   ```
3. **Для остальных стендов сгенерируй НОВЫЕ пары** (шаг 3.2). Если у них уже
   были `secret.enc.yaml`, зашифрованные старым ключом — расшифруй старым
   ключом один раз и перешифруй новым:
   ```bash
   # старый ключ во временной переменной (до перемещения/удаления):
   SOPS_AGE_KEY_FILE=/tmp/old.agekey bash scripts/decrypt.sh test
   bash scripts/encrypt.sh test      # уже возьмёт новый .envs/test/.agekey.public
   ```
4. **Обнови GitLab CI Variables** тех стендов, у которых сменился ключ
   (в примере — `SOPS_AGE_KEY_TEST`). Прод-переменная не меняется.
5. **Правь скрипты**: замени фолбэк на `./.agekey` (корень) на
   `.envs/$ENV/.agekey` / `.envs/$DEPLOY_ENV/.agekey` (раздел 7).
6. **Убедись, что корневые файлы исчезли** из git и с диска; в `.gitignore`
   правило `.agekey` остаётся (страховка на любом уровне).

## 5. Валидация после миграции/установки

```bash
# 1) Ключи в правильных местах, gitignore работает:
git check-ignore .envs/test/.agekey && git status --short   # .agekey не виден, .agekey.public — виден как untracked/modified

# 2) Round-trip (значения после encrypt→decrypt совпадают):
bash scripts/decrypt.sh test && cp .envs/test/secret.yaml /tmp/a.yaml
bash scripts/encrypt.sh test && bash scripts/decrypt.sh test && diff <(grep -o '^[A-Z_]*:.*' /tmp/a.yaml) <(grep -o '^[A-Z_]*:.*' .envs/test/secret.yaml)
# NB: sops нормализует YAML-форматирование (кавычки/пустые строки) — сверяй ЗНАЧЕНИЯ, не байты.

# 3) Recipient в enc-файле — публичный ключ этого стенда:
grep -c "$(cat .envs/test/.agekey.public)" .envs/test/secret.enc.yaml   # → 1

# 4) Деплой-скрипт резолвит ключ (безопасный прогон до реального деплоя — упадёт на следующем шаге):
CI_JOB_TOKEN= bash deploy_local.sh            # печатает "age-ключ: .envs/production/.agekey"
DEPLOY_ENV=test CI_JOB_TOKEN= bash deploy_local.sh

# 5) Guard тест-запуска на несуществующем стенде:
DEPLOY_ENV=noenv bash deployci-test.sh        # → "✗ Нет ключа расшифровки: создай .envs/noenv/.agekey"
```

## 6. Эталонные скрипты (копировать целиком)

### `scripts/encrypt.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# encrypt.sh — зашифровать .envs/<env>/secret.yaml → secret.enc.yaml (sops+age).
#
# Использование: bash scripts/encrypt.sh <test|production|...>
#
# Требования:
#   - sops (https://github.com/getsops/sops);
#   - файл .envs/<env>/.agekey.public (recipient, в git).
#
# Цикл: отредактировал secret.yaml → encrypt.sh <env> → закоммить secret.enc.yaml.
# =============================================================================
set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "${scriptDir}/.." || exit 1

ENV="${1:-}"
if [ -z "$ENV" ]; then
  echo "Usage: bash scripts/encrypt.sh <env>  (напр. test, production)" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/secret.yaml" ]; then
  echo "✗ Нет файла .envs/${ENV}/secret.yaml" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/.agekey.public" ]; then
  echo "✗ Нет файла .envs/${ENV}/.agekey.public — сгенерируй пару ключей: age-keygen -o .envs/${ENV}/.agekey" >&2
  exit 1
fi

export SOPS_AGE_RECIPIENTS="$(cat ".envs/${ENV}/.agekey.public")"
sops --encrypt --input-type yaml --output-type yaml \
  --age "${SOPS_AGE_RECIPIENTS}" \
  ".envs/${ENV}/secret.yaml" > ".envs/${ENV}/secret.enc.yaml"

echo "→ Зашифровано: .envs/${ENV}/secret.enc.yaml (не забудь закоммитить)"
```

### `scripts/decrypt.sh`

```bash
#!/usr/bin/env bash
# =============================================================================
# decrypt.sh — расшифровать .envs/<env>/secret.enc.yaml → secret.yaml (sops+age).
#
# Использование: bash scripts/decrypt.sh <test|production|...>
#
# Требуется приватный ключ per-env: env SOPS_AGE_KEY (содержимое ключа),
# SOPS_AGE_KEY_FILE или файл .envs/<env>/.agekey (gitignored).
# =============================================================================
set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "${scriptDir}/.." || exit 1

ENV="${1:-}"
if [ -z "$ENV" ]; then
  echo "Usage: bash scripts/decrypt.sh <env>  (напр. test, production)" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/secret.enc.yaml" ]; then
  echo "✗ Нет файла .envs/${ENV}/secret.enc.yaml" >&2
  exit 1
fi

# Приватный ключ: env SOPS_AGE_KEY > SOPS_AGE_KEY_FILE > .envs/<env>/.agekey
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  if [ -f ".envs/${ENV}/.agekey" ]; then
    export SOPS_AGE_KEY_FILE=".envs/${ENV}/.agekey"
  else
    echo "✗ Нет ключа: задай SOPS_AGE_KEY (или SOPS_AGE_KEY_FILE), либо создай .envs/${ENV}/.agekey (age-keygen -o .envs/${ENV}/.agekey)" >&2
    exit 1
  fi
fi

sops -d --input-type yaml --output-type yaml \
  ".envs/${ENV}/secret.enc.yaml" > ".envs/${ENV}/secret.yaml"

echo "→ Расшифровано: .envs/${ENV}/secret.yaml (файл в .gitignore, не коммитить)"
```

## 7. Снипеты интеграции в деплой-скрипты

### CI-деплой (аналог `docker/deploy_ci.sh`) — перед `sops -d`

```bash
# Ключ: env SOPS_AGE_KEY (в CI — GitLab Variables) > SOPS_AGE_KEY_FILE >
# per-env файл .envs/$DEPLOY_ENV/.agekey (локальный запуск без CI).
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  AGEKEY_FILE="$ROOT/.envs/$DEPLOY_ENV/.agekey"
  if [ -f "$AGEKEY_FILE" ]; then
    export SOPS_AGE_KEY_FILE="$AGEKEY_FILE"
    echo "→ SOPS_AGE_KEY не задан — использую ключ из .envs/$DEPLOY_ENV/.agekey"
  fi
fi
```

### Локальный деплой-обёртка (аналог `deploy_local.sh`) — строгий guard

```bash
# --- age-ключ (per-env: .envs/<DEPLOY_ENV>/.agekey) ---
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  AGEKEY_FILE="$ROOT/.envs/$DEPLOY_ENV/.agekey"
  if [ -f "$AGEKEY_FILE" ]; then
    export SOPS_AGE_KEY_FILE="$AGEKEY_FILE"
    echo "  age-ключ:   .envs/$DEPLOY_ENV/.agekey"
  else
    echo "✗ Нет age-ключа: передай SOPS_AGE_KEY/SOPS_AGE_KEY_FILE или создай .envs/$DEPLOY_ENV/.agekey (age-keygen -o .envs/$DEPLOY_ENV/.agekey)" >&2
    exit 1
  fi
fi
```

### Тест-запуск CI-деплоя (аналог `deployci-test.sh`) — guard в начале

```bash
export DEPLOY_ENV="${DEPLOY_ENV:-test}"
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ ! -f ".envs/$DEPLOY_ENV/.agekey" ]; then
  echo "✗ Нет ключа расшифровки: создай .envs/$DEPLOY_ENV/.agekey (age-keygen -o .envs/$DEPLOY_ENV/.agekey) или задай SOPS_AGE_KEY" >&2
  exit 1
fi
```

## 8. Чеклист портирования в другой проект

- [ ] `sops` и `age-keygen` доступны (или есть `ensure_sops_yq`);
- [ ] папки `.envs/<env>/` по числу стендов, `public.yaml` + `secret.yaml.example`;
- [ ] `.gitignore`: `.agekey` (любой уровень) + `.envs/*/secret.yaml`;
- [ ] пара ключей **на каждый стенд**: `.envs/<env>/.agekey` (gitignored) +
      `.envs/<env>/.agekey.public` (в git, закоммичен);
- [ ] `scripts/encrypt.sh` / `scripts/decrypt.sh` скопированы, работают;
- [ ] деплой-скрипты резолвят ключ из `.envs/$DEPLOY_ENV/.agekey` (снипеты выше);
- [ ] GitLab CI Variables: `SOPS_AGE_KEY_<ENV>` для каждого стенда
      (protected + masked), джобы мапят их в `SOPS_AGE_KEY` + `DEPLOY_ENV`;
- [ ] round-trip валидация пройдена (раздел 5);
- [ ] в доке проекта добавлена ссылка на этот файл.