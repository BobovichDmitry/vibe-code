#!/usr/bin/env bash
# =============================================================================
# deploy_ci.sh — CI-деплой VibeSetup UI (GitLab CI) по SOPS-зашифрованным энвам.
# =============================================================================
# Вызывается джобой deploy:* из .gitlab-ci.yml (можно и вручную для отладки).
#
# Окружение (от CI):
#   DEPLOY_ENV     — стенд (test | production) — какие .envs/<env>/* использовать;
#   SOPS_AGE_KEY   — приватный age-ключ для расшифровки .envs/<env>/secret.enc.yaml
#                    (в CI — из GitLab Variables; masked, никогда в argv/файлах);
#   CI_REGISTRY    — хост container registry (predefined в CI);
#   CI_JOB_TOKEN   — временный токен для docker pull из Registry (живёт в рамках джобы);
#   FRONTEND_IMAGE — полный ref frontend-образа (напр. registry/.../frontend:abc1234);
#   BACKEND_IMAGE  — полный ref backend-образа.
#
# Поток:
#   1. Расшифровывает .envs/$DEPLOY_ENV/secret.enc.yaml (sops+age), мержит с
#      .envs/$DEPLOY_ENV/public.yaml (yq) и экспортирует всё как переменные
#      окружения; base64 приватного ключа деплоя (DEPLOY_SSH_KEY) → во временный
#      id_rsa (chmod 600).
#   2. SSH на сервер: ставит ansible с нуля (если нет) — подготовка пустого сервера.
#   3. Собирает tar.gz исходников + deploy-env.sh (переменные из .envs/),
#      заливает через ssh, распаковывает на сервере.
#   4. Генерирует .app.secrets (db_password, jwt_secret), если нет; собирает
#      ansible/vars.yml; логинится в Registry ВРЕМЕННЫМ токеном (CI_JOB_TOKEN).
#   5. Запускает ansible-playbook: роли deps (docker) + proxy (nginx-proxy+acme)
#      + deploy (docker/.env + PULL образов из Registry, БЕЗ сборки) + healthcheck.
#   6. Логаут из Registry (токен временный) + финальная HTTP-проверка.
#
# Сервер НЕ собирает образы: только pull из Registry. Ручной деплой без CI —
# ./deploy.sh (не зависит от этого скрипта).
#
# --- Локальный тест-запуск (без GitLab) ---
# Ключ расшифровки: env SOPS_AGE_KEY, SOPS_AGE_KEY_FILE или файл ./.agekey в
# корне репо (gitignored). Образы — собранные пайплайном теги из Registry.
#
#   DEPLOY_ENV=test FRONTEND_IMAGE="registry.../frontend:master" \
#   BACKEND_IMAGE="registry.../backend:master" bash docker/deploy_ci.sh
#
# Registry-логин выполняется только если заданы CI_REGISTRY и CI_JOB_TOKEN
# (т.е. в CI). При ручном тестовом запуске они не нужны: считается, что
# авторизация в registry (docker login) на сервере уже сделана руками.
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd )"
cd "$ROOT"

# --- Дублируем весь вывод в logs/deploy-ci.log (и в stdout/CI-джобу) ---
mkdir -p "$ROOT/logs"
LOG_FILE="$ROOT/logs/deploy-ci.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Маркер окончания деплоя (trap EXIT): агент/скрипт может ждать строку
# DEPLOY-FINISHED (успех) или DEPLOY-FAILED (ошибка) в stdout или logs/deploy-ci.log ---
deploy_exit_marker() {
  local code=$?
  rm -rf "${BUNDLE_DIR:-}" 2>/dev/null || true
  if [ "$code" = "0" ]; then
    echo "### DEPLOY-FINISHED: deploy_ci.sh завершился успешно (exit 0) ###"
  else
    echo "### DEPLOY-FAILED: deploy_ci.sh завершился с ошибкой (exit $code) ###"
  fi
}
trap deploy_exit_marker EXIT

echo ""
echo "===== deploy_ci.sh — $(date '+%Y-%m-%d %H:%M:%S') ====="

# --- 1. CI-переменные ---
: "${DEPLOY_ENV:?✗ DEPLOY_ENV не задан (test|production) — какое .envs/<env> использовать}"
[ -d "$ROOT/.envs/$DEPLOY_ENV" ] || { echo "✗ Нет окружения .envs/$DEPLOY_ENV" >&2; exit 1; }
: "${FRONTEND_IMAGE:?✗ FRONTEND_IMAGE не задан (напр. \$CI_REGISTRY_IMAGE/frontend:<sha>)}"
: "${BACKEND_IMAGE:?✗ BACKEND_IMAGE не задан (напр. \$CI_REGISTRY_IMAGE/backend:<sha>)}"

# CI_REGISTRY/CI_JOB_TOKEN — опциональны (нужны только для логина в Registry;
# в CI задаются автоматически, при ручном тесте — скипаем, если авторизация
# в registry уже сделана на сервере руками; или задай REGISTRY_USER+CI_JOB_TOKEN).
REGISTRY_LOGGED_IN=0
for v in "$FRONTEND_IMAGE" "$BACKEND_IMAGE"; do
  case "$v" in *[\"\'\ ]*|*$'\n'*) echo "✗ Недопустимые символы в: $v" >&2; exit 1;; esac
done

# --- 1а. Зависимости раннера: ssh/curl (в CI-образе ubuntu их нет; на shell-раннере
# уже есть — apt без root там невозможен, поэтому ставим только если реально нужно) ---
if ! command -v ssh >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  if [ "$(id -u)" = "0" ]; then
    apt-get update -qq && apt-get install -y -qq openssh-client ca-certificates curl
  else
    echo "✗ ssh/curl не найдены, а apt требует root — установи openssh-client на раннере (или используй docker executor)." >&2
    exit 1
  fi
fi

# --- 1б. Зависимости раннера: sops и yq (binaries, официальные release-сборки) ---
# Порядок поиска: уже установлены → /opt/binaries (несколько форматов путей; раннер
# может быть без интернет-доступа) → скачивание с ретраями (DNS/сеть к GitHub
# периодически флапают — без ретраиев падают деплои).
ensure_sops_yq() {
  local TOOL_BIN="$(mktemp -d /tmp/deploy-tools.XXXXXX)"
  export PATH="$TOOL_BIN:$PATH"
  local OS_ARCH="$(uname -s)_$(uname -m)"
  case "$OS_ARCH" in
    Linux_x86_64)  local arch="linux.amd64" ;;
    Linux_aarch64) local arch="linux.arm64" ;;
    Darwin_x86_64) local arch="darwin.amd64" ;;
    Darwin_arm64)  local arch="darwin.arm64" ;;
    *) echo "✗ sops/yq: непонятная платформа '$OS_ARCH' — установи sops и yq вручную (https://github.com/getsops/sops, https://github.com/mikefarah/yq)" >&2; exit 1 ;;
  esac
  # Скачивание с ретраями: DNS/сеть к GitHub периодически флапают
  dl_with_retry() {
    local url="$1" dest="$2" i
    for i in 1 2 3; do
      if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 "$url" -o "$dest" && [ -s "$dest" ]; then
        return 0
      fi
      echo "→ Попытка $i скачать $(basename "$dest") не удалась — retry..." >&2
      sleep 3
    done
    echo "✗ Не удалось скачать $url после 3 попыток" >&2
    return 1
  }
  # Поиск заранее положенного бинарника на /opt/binaries. КАНДИДАТ ОБЯТЕЛЬНО
  # проверяется запуском (--version): в /opt/binaries/<name> может лежать и
  # распакованная папка (у неё -x тоже истинен), и битый бинарник.
  resolve_preinstalled() {
    local name="$1" cand found
    for cand in \
      "/opt/binaries/$name" \
      "/opt/binaries/$name.$(uname -m)" \
      "/opt/binaries/$(uname -m)/$name" \
      "/opt/binaries/$name-$(uname -s | tr '[:upper:]' '[:lower:]')" \
      "/opt/binaries/$name"/*"$name"* \
      "/opt/binaries/$name"/*/*"$name"*; do
      # Только обычный исполняемый файл ( НЕ директория!
      [ -f "$cand" ] || continue
      [ -x "$cand" ] || continue
      if "$cand" --version >/dev/null 2>&1; then
        found="$cand"
        break
      fi
    done
    [ -n "${found:-}" ] || return 1
    # Копия (не symlink): бинарник точно останется рабочим в isolate-контексте
    cp "$found" "$TOOL_BIN/$name" && echo "$found"
  }
  if ! command -v sops >/dev/null 2>&1; then
    found="$(resolve_preinstalled sops)" || found=""
    if [ -n "$found" ]; then
      echo "→ sops: использую $found"
    else
      echo "→ Установка sops (v3.9.4)..."
      dl_with_retry "https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.${arch}" "$TOOL_BIN/sops" && chmod +x "$TOOL_BIN/sops"
    fi
  fi
  if ! command -v yq >/dev/null 2>&1; then
    found="$(resolve_preinstalled yq)" || found=""
    if [ -n "$found" ]; then
      echo "→ yq: использую $found"
    else
      echo "→ Установка yq (v4.47.2)..."
      local os="${arch%%.*}"
      local yq_arch="$(uname -m)"
      [ "$yq_arch" = "x86_64" ] && yq_arch="amd64"
      [ "$yq_arch" = "aarch64" ] && yq_arch="arm64"
      dl_with_retry "https://github.com/mikefarah/yq/releases/download/v4.47.2/yq_${os}_${yq_arch}" "$TOOL_BIN/yq" && chmod +x "$TOOL_BIN/yq"
    fi
  fi
  # Финальная проверка — РЕАЛЬНЫЙ запуск (command -v недостаточно: ловит битые
  # бинарники и symlink'и на директории).
  sops --version >/dev/null 2>&1 || { echo "✗ sops не работает: $(sops --version 2>&1 | head -1)" >&2; exit 1; }
  yq --version >/dev/null 2>&1  || { echo "✗ yq не работает: $(yq --version 2>&1 | head -1)" >&2; exit 1; }
}
ensure_sops_yq

# --- 2. Расшифровка энвов (.envs/$DEPLOY_ENV) + временный id_rsa ---
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  if [ -f "$ROOT/.agekey" ]; then
    export SOPS_AGE_KEY_FILE="$ROOT/.agekey"
    echo "→ SOPS_AGE_KEY не задан — использую ключ из ./.agekey"
  fi
fi
SECRET_ENC="$ROOT/.envs/$DEPLOY_ENV/secret.enc.yaml"
PUBLIC_YML="$ROOT/.envs/$DEPLOY_ENV/public.yaml"
[ -f "$SECRET_ENC" ] || { echo "✗ Нет файла $SECRET_ENC — сгенерируй (scripts/encrypt.sh $DEPLOY_ENV), см. docs/deployment.md" >&2; exit 1; }
[ -f "$PUBLIC_YML" ] || { echo "✗ Нет файла $PUBLIC_YML" >&2; exit 1; }

echo "→ Расшифровка .envs/$DEPLOY_ENV/secret.enc.yaml (sops+age)..."
SECRET_DATA="$(sops -d --input-type yaml --output-type yaml "$SECRET_ENC")"

# Мерж secret (перекрывает) + public → export UPPERCASE-ключей как переменных окружения
MERGED="$(yq ea -o p '. as $item ireduce ({}; . * $item)' <(echo "$SECRET_DATA") <(cat "$PUBLIC_YML"))"
# Формат вывода yq -o p: строки "KEY = value" (пробелы вокруг "=").
# Пропускаем пустые строки и комментарии; обёрнутые в кавычки значения разворачиваем.
# ALL_DEPLOY_KEYS — ВСЕ ключи из .envs/<env>/ (они и есть источник правды для деплоя:
# форк добавляет переменную в public.yaml/secret.enc.yaml — она едет на сервер как есть).
ALL_DEPLOY_KEYS=""
while IFS= read -r line; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  if [[ "$line" == *' = '* ]]; then
    key="${line%% = *}"; val="${line#* = }"
  elif [[ "$line" == *=* ]]; then
    key="${line%%=*}"; val="${line#*=}"
  else
    continue
  fi
  # yq обёрнул значение в кавычки (напр. KEY = "va lue") — снимаем их
  if [ ${#val} -ge 2 ] && [ "${val:0:1}" = '"' ] && [ "${val: -1}" = '"' ]; then
    val="${val:1:${#val}-2}"
  fi
  export "$key=$val"
  ALL_DEPLOY_KEYS="$ALL_DEPLOY_KEYS $key"

done <<< "$MERGED"

# SHA коммита из CI (чтобы GET /api/version показывал, какая сборка запущена).
# Едет на сервер тем же generic pass-through (extra_env), если не задан вручную.
if [ -z "${APP_COMMIT_SHA:-}" ] && [ -n "${CI_COMMIT_SHORT_SHA:-}" ]; then
  export APP_COMMIT_SHA="$CI_COMMIT_SHORT_SHA"
  ALL_DEPLOY_KEYS="$ALL_DEPLOY_KEYS APP_COMMIT_SHA"
fi

BUNDLE_DIR="$(mktemp -d /tmp/deploy-ci.XXXXXX)"
chmod 700 "$BUNDLE_DIR"

if [ -z "${DEPLOY_SSH_KEY:-}" ]; then
  echo "✗ В secret.enc.yaml нет DEPLOY_SSH_KEY (base64 приватного ключа деплоя)" >&2
  exit 1
fi
base64 -d <<<"$DEPLOY_SSH_KEY" > "$BUNDLE_DIR/id_rsa"
chmod 600 "$BUNDLE_DIR/id_rsa"

# --- 3. Контракты переменных ---

: "${SSH_HOST:?✗ В .envs/$DEPLOY_ENV нет SSH_HOST (public.yaml)}"
: "${SSH_USER:?✗ В .envs/$DEPLOY_ENV нет SSH_USER (public.yaml)}"
: "${DOMAIN:?✗ В .envs/$DEPLOY_ENV нет DOMAIN (public.yaml)}"
: "${LETSENCRYPT_EMAIL:?✗ В .envs/$DEPLOY_ENV нет LETSENCRYPT_EMAIL (public.yaml)}"
: "${ADMIN_PASSWORD:?✗ В .envs/$DEPLOY_ENV нет ADMIN_PASSWORD (secret.enc.yaml)}"
: "${PROJECT_NAME:?✗ В .envs/$DEPLOY_ENV нет PROJECT_NAME (public.yaml) — укажи слаг проекта (напр. my-project-test)}"
SSH_PORT="${SSH_PORT:-22}"
ADMIN_LOGIN="${ADMIN_LOGIN:-admin}"
BRAND_TITLE="${BRAND_TITLE:-VibeSetup UI}"
BRAND_FAVICON_URL="${BRAND_FAVICON_URL:-/favicon.svg}"
PROJECT_DIR="${PROJECT_DIR:-/opt/$PROJECT_NAME}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/$PROJECT_NAME.tar.gz}"
PROXY_DIR="${PROXY_DIR:-/opt/nginx-proxy}"
unset SSH_KEY || true   # ключ деплоя — из DEPLOY_SSH_KEY (secret.enc.yaml)

echo "→ CI-деплой $DOMAIN на $SSH_USER@$SSH_HOST:$SSH_PORT (project: $PROJECT_NAME → $PROJECT_DIR)"

# --- Best-effort проверка DNS (non-interactive: только предупреждение) ---
if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  PY="$(command -v python3 || command -v python)"
  RESOLVED="$("$PY" -c "import socket,sys
try: print(socket.gethostbyname(sys.argv[1]))
except Exception: print('')" "$DOMAIN" 2>/dev/null || true)"
  if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$SSH_HOST" ]; then
    echo "⚠  $DOMAIN резолвится в '$RESOLVED', а не в '$SSH_HOST' — Let's Encrypt не выпустит сертификат." >&2
  fi
fi

SSH_BIN="${SSH_BIN:-ssh}"

# --- Проверка host-ключа сервера ---
# По умолчанию: accept-new (новые хосты доверяем, ИЗМЕНИВШИЕСЯ ключи — ошибка).
# DEPLOY_SKIP_HOST_KEY_CHECK=1 (GitLab Variable или env) — отключает проверку
# полностью (для пересозданных/переустановленных серверов; НЕБЕЗОПАСНО — MITM).
if [ "${DEPLOY_SKIP_HOST_KEY_CHECK:-0}" = "1" ]; then
  echo "⚠  DEPLOY_SKIP_HOST_KEY_CHECK=1 — проверка host key сервера ОТКЛЮЧЕНА (небезопасно)."
  HOST_KEY_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
else
  HOST_KEY_OPTS=(-o StrictHostKeyChecking=accept-new)
fi

SSH_BASE=(-i "$BUNDLE_DIR/id_rsa"
          "${HOST_KEY_OPTS[@]}"
          -o IdentitiesOnly=yes
          -o ConnectTimeout=15
          -p "$SSH_PORT")
SSH_CMD=("$SSH_BIN" "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}")

# --- 4. Установка ansible на сервере с нуля ---
echo "→ Установка ansible на сервере (если нет)..."
"${SSH_CMD[@]}" bash -s <<'REMOTE_PREP'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if ! command -v ansible-playbook >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y ansible python3
fi
ansible-playbook --version | head -1
echo "OK prep"
REMOTE_PREP

# --- Экранирование значений для deploy-env.sh (двойные кавычки) ---
eq() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  s="${s//\`/\\\`}"
  printf '"%s"' "$s"
}

# --- 5. Архив исходников + deploy-env.sh ---
echo "→ Сборка архива исходников..."
ARCHIVE_LOCAL="/tmp/${PROJECT_NAME}.tar.gz"
DEPLOY_ENV_LOCAL="/tmp/${PROJECT_NAME}-deploy-env.sh"
rm -f "$ARCHIVE_LOCAL" "$DEPLOY_ENV_LOCAL"
# Архив: серверу нужны только ansible/, docker/ и корневые файлы — код
# приложения приезжает в Docker-образах из Registry. Лишнее не отправляем.
tar --exclude=node_modules \
    --exclude=dist \
    --exclude=.git \
    --exclude=logs \
    --exclude=data \
    --exclude=playwright-report \
    --exclude=test-results \
    --exclude=.env \
    --exclude=.env.local \
    --exclude=.app.secrets \
    --exclude=.app.s3 \
    --exclude=apps \
    --exclude=e2e \
    --exclude=docs \
    --exclude=tasks \
    --exclude=.idea \
    --exclude=.pi \
    --exclude=.ai \
    --exclude='*.tsbuildinfo' \
    --exclude=deploy-vars.yml \
    --exclude=questions.md \
    --exclude=readme-for-agents.md \
    -czf "$ARCHIVE_LOCAL" -C "$ROOT" .
echo "   архив: $(du -h "$ARCHIVE_LOCAL" | cut -f1)"

cat > "$DEPLOY_ENV_LOCAL" <<EOF
export DOMAIN=$(eq "$DOMAIN")
export LETSENCRYPT_EMAIL=$(eq "$LETSENCRYPT_EMAIL")
export BRAND_TITLE=$(eq "$BRAND_TITLE")
export BRAND_FAVICON_URL=$(eq "$BRAND_FAVICON_URL")
export ADMIN_LOGIN=$(eq "$ADMIN_LOGIN")
export ADMIN_PASSWORD=$(eq "$ADMIN_PASSWORD")
export PROJECT_NAME=$(eq "$PROJECT_NAME")
export PROJECT_DIR=$(eq "$PROJECT_DIR")
export ARCHIVE_PATH=$(eq "$ARCHIVE_PATH")
export PROXY_DIR=$(eq "$PROXY_DIR")
export SSH_HOST=$(eq "$SSH_HOST")
EOF

# Прокидываем на сервер ВСЕ переменные из .envs/$DEPLOY_ENV (merged yq) + список
# «дополнительно прокидываемых» ключей EXTRA_ENV_KEYS. Всё, что форк закоммитил
# в public.yaml/secret.enc.yaml, едет на сервер без правок скрипта.
# BASE_DEPLOY_KEYS обрабатываются отдельными полями vars.yml — в extra_env не дублируем.
BASE_DEPLOY_KEYS="DOMAIN LETSENCRYPT_EMAIL BRAND_TITLE BRAND_FAVICON_URL ADMIN_LOGIN ADMIN_PASSWORD PROJECT_NAME PROJECT_DIR ARCHIVE_PATH PROXY_DIR SSH_HOST SSH_USER SSH_PORT DEPLOY_SSH_KEY DEPLOY_SKIP_HOST_KEY_CHECK"
EXTRA_ENV_KEYS=""
for _v in $ALL_DEPLOY_KEYS; do
  case " $BASE_DEPLOY_KEYS " in
    *" $_v "*) continue ;;
  esac
  EXTRA_ENV_KEYS="$EXTRA_ENV_KEYS $_v"
done
for _v in $ALL_DEPLOY_KEYS; do
  echo "export $_v=$(eq "${!_v:-}")" >> "$DEPLOY_ENV_LOCAL"
done
echo "export EXTRA_ENV_KEYS=\"$EXTRA_ENV_KEYS\"" >> "$DEPLOY_ENV_LOCAL"

echo "→ Загрузка архива + env на сервер..."
# Загрузка через ssh stdin (binary-safe) — не через sftp: sftp ломается на Windows
# (Git Bash: exec /usr/bin/ssh not found), а на CI-раннере sftp не нужен.
"${SSH_CMD[@]}" "cat > '$ARCHIVE_PATH'" < "$ARCHIVE_LOCAL"
"${SSH_CMD[@]}" "cat > '/opt/.${PROJECT_NAME}-deploy-env.sh' && chmod 600 '/opt/.${PROJECT_NAME}-deploy-env.sh'" < "$DEPLOY_ENV_LOCAL"

# --- 6. Логин в Registry ВРЕМЕННЫМ токеном (token идёт через stdin, не в argv) ---
# Только если заданы CI_REGISTRY и CI_JOB_TOKEN (в CI — всегда). Ручной тест-запуск
# без них: авторизация в registry на сервере делается руками, ЛИБО передай
# REGISTRY_USER=<логин> и CI_JOB_TOKEN=<PAT/deploy-token> — тогда логин выполнит скрипт.
REGISTRY_USER="${REGISTRY_USER:-gitlab-ci-token}"
if [ -n "${CI_REGISTRY:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
  echo "→ docker login в $CI_REGISTRY (как $REGISTRY_USER, токен через stdin)..."
  printf '%s' "$CI_JOB_TOKEN" | \
    "$SSH_BIN" "${HOST_KEY_OPTS[@]}" -o IdentitiesOnly=yes -i "$BUNDLE_DIR/id_rsa" -p "$SSH_PORT" \
        "${SSH_USER}@${SSH_HOST}" "docker login '$CI_REGISTRY' --username '$REGISTRY_USER' --password-stdin"
  REGISTRY_LOGGED_IN=1
else
  echo "→ CI_REGISTRY/CI_JOB_TOKEN не заданы — docker login пропущен (считаю, что авторизация в registry на сервере уже есть)."
fi

# --- 7. Распаковка + секреты + vars.yml + ansible-playbook (pull, без build) ---
echo "→ Распаковка, генерация .app.secrets, запуск ansible-playbook..."
"${SSH_CMD[@]}" env PROJECT_NAME="$PROJECT_NAME" \
  FRONTEND_IMAGE="$FRONTEND_IMAGE" BACKEND_IMAGE="$BACKEND_IMAGE" bash -s <<'REMOTE_DEPLOY'
set -euo pipefail
# shellcheck disable=SC1091
source "/opt/.${PROJECT_NAME}-deploy-env.sh"

PROJECT_DIR="${PROJECT_DIR:-/opt/${PROJECT_NAME}}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/${PROJECT_NAME}.tar.gz}"

mkdir -p "$PROJECT_DIR"
echo "→ Распаковка архива в $PROJECT_DIR..."
tar -xzf "$ARCHIVE_PATH" -C "$PROJECT_DIR"
cd "$PROJECT_DIR"

# --- S3: персистентность между деплоями (.app.s3-кеш) ---
# Если в текущем деплое полный набор S3_* пришёл — кешируем в .app.s3
# (umask 077, shell-экранирование). Если НЕ пришёл — переиспользуем кеш,
# чтобы повторный деплой без S3-переменных не затирал настроенный S3.
S3_ENV_VARS="S3_ENDPOINT S3_PUBLIC_URL S3_REGION S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY S3_KEY_PREFIX S3_FORCE_PATH_STYLE S3_UPLOAD_EXPIRES S3_DOWNLOAD_EXPIRES S3_CROPPED_SUBFOLDER S3_CROPPED_TTL_DAYS S3_IMAGE_MAX_DIM S3_PRESIGN_VARIANT_EXPIRES"
S3_REQUIRED_VARS="S3_ENDPOINT S3_BUCKET S3_ACCESS_KEY S3_SECRET_KEY"
S3_COMPLETE=1
for _v in $S3_REQUIRED_VARS; do
  [ -n "${!_v:-}" ] || S3_COMPLETE=0
done
if [ "$S3_COMPLETE" = "1" ]; then
  umask 077
  : > .app.s3
  for _v in $S3_ENV_VARS; do
    printf 'export %s=%q\n' "$_v" "${!_v:-}" >> .app.s3
  done
  echo "→ S3-переменные закешированы в $PROJECT_DIR/.app.s3"
elif [ -f .app.s3 ]; then
  echo "→ S3_* в текущем деплое не заданы — переиспользую кеш .app.s3"
  # shellcheck disable=SC1091
  set -a; source ./.app.s3; set +a
else
  echo "→ S3 не настроен и кеша .app.s3 нет — приложение стартует без S3"
fi

# --- .app.secrets (db_password, jwt_secret) — генерируются один раз ---
if [ ! -f .app.secrets ]; then
  DBPW="$(openssl rand -hex 18)"
  JWT="$(openssl rand -hex 32)"
  umask 077
  printf 'db_password: "%s"\njwt_secret: "%s"\n' "$DBPW" "$JWT" > .app.secrets
  echo "→ Сгенерирован $PROJECT_DIR/.app.secrets (db_password, jwt_secret)"
else
  echo "→ .app.secrets уже есть — переиспользуем"
fi

# --- ansible/vars.yml (vars из бандл-.env + секреты из .app.secrets) ---
umask 077
cat > ansible/vars.yml <<YML
server_ip: "$SSH_HOST"
domain: "$DOMAIN"
letsencrypt_email: "$LETSENCRYPT_EMAIL"
project_name: "$PROJECT_NAME"
project_dir: "$PROJECT_DIR"
archive_path: "$ARCHIVE_PATH"
proxy_dir: "$PROXY_DIR"
brand_title: "$BRAND_TITLE"
brand_favicon_url: "$BRAND_FAVICON_URL"
admin_login: "$ADMIN_LOGIN"
admin_password: "$ADMIN_PASSWORD"
db_username: "$PROJECT_NAME"
db_name: "${PROJECT_NAME}_db"
YML
# --- Дополнительно прокидываемые переменные окружения (extra_env) ---
# Любая переменная, закоммиченная форком в .envs/<env>/{public,secret}.yaml
# (кроме базовых ключей деплоя — они отдельные поля vars.yml), уезжает в docker/env
# как есть: vars.yml: extra_env: { KEY: "value" } → env.j2 рендерит "KEY=value".
# Экранирование значений для YAML-строки в двойных кавычках (\ и ").
yml_str() { local s="${2//\\/\\\\}"; s="${s//\"/\\"}"; printf '%s: "%s"\n' "$1" "$s"; }
cat >> ansible/vars.yml <<YML
extra_env:
YML
for _v in ${EXTRA_ENV_KEYS:-}; do
  yml_str "$_v" "${!_v:-}" | sed 's/^/  /' >> ansible/vars.yml
done
cat .app.secrets >> ansible/vars.yml
chmod 600 ansible/vars.yml

# --- ansible: deps (docker) + proxy (nginx-proxy) + deploy (pull образов) + healthcheck ---
cd "$PROJECT_DIR/ansible"
echo "→ ansible-playbook playbook.yml (CI-режим: pull из Registry, без сборки)"
ansible-playbook playbook.yml -e @vars.yml \
  -e "frontend_image=$FRONTEND_IMAGE backend_image=$BACKEND_IMAGE"

echo "✅ CI-деплой завершён."

# Транзитные файлы с секретами удаляем: они пересоздаются при каждом деплое.
# Остаются только персистентные 0600-кешы .app.secrets/.app.s3 (нужны переиспользования секретов).
rm -f "/opt/.${PROJECT_NAME}-deploy-env.sh" "$PROJECT_DIR/ansible/vars.yml"
REMOTE_DEPLOY

# --- 8. Логаут из Registry (токен временный) — best-effort ---
if [ "$REGISTRY_LOGGED_IN" = "1" ]; then
  "$SSH_BIN" "${HOST_KEY_OPTS[@]}" -o IdentitiesOnly=yes -i "$BUNDLE_DIR/id_rsa" -p "$SSH_PORT" \
      "${SSH_USER}@${SSH_HOST}" "docker logout '$CI_REGISTRY'" >/dev/null 2>&1 || true
fi

# --- 9. Финальная проверка ---
# Транзитный env-файл с паролями на локальной машине тоже удаляем.
rm -f "$DEPLOY_ENV_LOCAL"
echo
echo "→ Проверка: https://$DOMAIN/api/users/count"
echo "  (сертификат может выпускаться до ~1 мин после первого запуска)"
HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "https://$DOMAIN/api/users/count" 2>/dev/null || echo "000")"
echo "  HTTP $HTTP_CODE  (ожидается 200)"
[ "$HTTP_CODE" = "200" ] || echo "⚠  Healthcheck не 200 — смотри логи на сервере: cd $PROJECT_DIR/docker && docker compose -p $PROJECT_NAME -f docker-compose.prod.yml logs"