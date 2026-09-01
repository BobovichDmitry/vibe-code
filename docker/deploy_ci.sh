#!/usr/bin/env bash
# =============================================================================
# deploy_ci.sh — CI-деплой VibeSetup UI (GitLab CI) из base64-бандла.
# =============================================================================
# Вызывается джобой deploy:* из .gitlab-ci.yml (можно и вручную для отладки).
#
# Окружение (от CI):
#   DEPLOY_BUNDLE   — base64( tar.gz[ id_rsa, .env ] ) — см. scripts/make_deploy_bundle.sh
#                     .env — тот же формат, что для deploy.sh (SSH_HOST, SSH_USER,
#                     DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD, PROJECT_NAME,
#                     опц. SSH_PORT/PROJECT_DIR/PROXY_DIR/BRAND_*/ADMIN_LOGIN).
#                     SSH_KEY из .env игнорируется — ключ берётся из бандла.
#   CI_REGISTRY     — хост container registry (predefined в CI)
#   CI_JOB_TOKEN    — временный токен для docker pull из Registry (живёт в рамках джобы)
#   FRONTEND_IMAGE  — полный ref frontend-образа (напр. registry/.../frontend:abc1234)
#   BACKEND_IMAGE   — полный ref backend-образа
#
# Поток:
#   1. Распаковывает бандл во временный каталог (ключ + .env).
#   2. SSH на сервер: ставит ansible с нуля (если нет) — подготовка пустого сервера.
#   3. Собирает tar.gz исходников + deploy-env.sh (переменные из бандл-.env),
#      заливает через sftp, распаковывает на сервере.
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
# Бандл берётся из DEPLOY_BUNDLE, а если он пуст — из файла ./.ci-bundle в
# корне репо (см. .gitignore — файл с ключом коммитить НЕЛЬЗЯ):
#   scripts/make_deploy_bundle.sh <id_rsa> <.env> > .ci-bundle
#
# Registry-логин выполняется только если заданы CI_REGISTRY и CI_JOB_TOKEN
# (т.е. в CI). При ручном тестовом запуске они не нужны: считается, что
# авторизация в registry (docker login) на сервере уже сделана руками.
#
# Пример тестового запуска на реальный сервер (public-образы, registry уже
# авторизован на сервере):
#   DEPLOY_BUNDLE="$(cat .ci-bundle)" \
#   FRONTEND_IMAGE="nginx:alpine" BACKEND_IMAGE="nginx:alpine" \
#     bash docker/deploy_ci.sh
#
# Тот же запуск с образами из GitLab Registry:
#   DEPLOY_BUNDLE="$(cat .ci-bundle)" \
#   CI_REGISTRY="registry.gitlab.com/ns/proj" CI_JOB_TOKEN="<deploy-token>" \
#   FRONTEND_IMAGE="registry.gitlab.com/ns/proj/frontend:abc123" \
#   BACKEND_IMAGE="registry.gitlab.com/ns/proj/backend:abc123" \
#     bash docker/deploy_ci.sh
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd )"
cd "$ROOT"

# --- 1. CI-переменные ---
# Бандл: из DEPLOY_BUNDLE (CI) или из файла ./.ci-bundle (локальный тест-запуск).
if [ -z "${DEPLOY_BUNDLE:-}" ] && [ -f "$ROOT/.ci-bundle" ]; then
  echo "→ DEPLOY_BUNDLE не задан — читаю бандл из ./.ci-bundle"
  DEPLOY_BUNDLE="$(tr -d '[:space:]' < "$ROOT/.ci-bundle")"
fi
: "${DEPLOY_BUNDLE:?✗ DEPLOY_BUNDLE не задан и ./.ci-bundle не найден — положи бандл в CI/CD Variables (DEPLOY_BUNDLE_TEST / DEPLOY_BUNDLE_PRODUCTION) или сформируй: scripts/make_deploy_bundle.sh <id_rsa> <.env> > .ci-bundle}"
: "${FRONTEND_IMAGE:?✗ FRONTEND_IMAGE не задан (напр. \$CI_REGISTRY_IMAGE/frontend:<sha>)}"
: "${BACKEND_IMAGE:?✗ BACKEND_IMAGE не задан (напр. \$CI_REGISTRY_IMAGE/backend:<sha>)}"

# CI_REGISTRY/CI_JOB_TOKEN — опциональны (нужны только для логина в Registry;
# в CI задаются автоматически, при ручном тесте — скипаем, если авторизация
# в registry уже сделана на сервере руками).
REGISTRY_LOGGED_IN=0
for v in "$FRONTEND_IMAGE" "$BACKEND_IMAGE"; do
  case "$v" in *[\"\'\ ]*|*$'\n'*) echo "✗ Недопустимые символы в: $v" >&2; exit 1;; esac
done

# --- 2. Распаковка бандла (SSH-ключ + .env) ---
BUNDLE_DIR="$(mktemp -d /tmp/deploy-ci.XXXXXX)"
chmod 700 "$BUNDLE_DIR"
trap 'rm -rf "$BUNDLE_DIR"' EXIT

echo "→ Распаковка бандла..."
base64 -d <<<"$DEPLOY_BUNDLE" | tar -C "$BUNDLE_DIR" -xz
[ -f "$BUNDLE_DIR/id_rsa" ] || { echo "✗ В бандле нет id_rsa" >&2; exit 1; }
[ -f "$BUNDLE_DIR/.env" ]   || { echo "✗ В бандле нет .env" >&2; exit 1; }
chmod 600 "$BUNDLE_DIR/id_rsa"

# --- 3. .env из бандла ---
set -a; source "$BUNDLE_DIR/.env"; set +a

: "${SSH_HOST:?✗ В бандл-.env нет SSH_HOST}"
: "${SSH_USER:?✗ В бандл-.env нет SSH_USER}"
: "${DOMAIN:?✗ В бандл-.env нет DOMAIN}"
: "${LETSENCRYPT_EMAIL:?✗ В бандл-.env нет LETSENCRYPT_EMAIL}"
: "${ADMIN_PASSWORD:?✗ В бандл-.env нет ADMIN_PASSWORD}"
: "${PROJECT_NAME:?✗ В бандл-.env нет PROJECT_NAME — укажи слаг проекта (напр. my-project-test)}"
SSH_PORT="${SSH_PORT:-22}"
ADMIN_LOGIN="${ADMIN_LOGIN:-admin}"
BRAND_TITLE="${BRAND_TITLE:-VibeSetup UI}"
BRAND_FAVICON_URL="${BRAND_FAVICON_URL:-/favicon.svg}"
PROJECT_DIR="${PROJECT_DIR:-/opt/$PROJECT_NAME}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/$PROJECT_NAME.tar.gz}"
PROXY_DIR="${PROXY_DIR:-/opt/nginx-proxy}"
unset SSH_KEY || true   # из бандла ключ не нужен — он уже в $BUNDLE_DIR/id_rsa

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
SSH_BASE=(-i "$BUNDLE_DIR/id_rsa"
          -o StrictHostKeyChecking=accept-new
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
tar --exclude=node_modules \
    --exclude=dist \
    --exclude=.git \
    --exclude=logs \
    --exclude=data \
    --exclude=playwright-report \
    --exclude=test-results \
    --exclude=.env \
    --exclude=.app.secrets \
    --exclude='*.tsbuildinfo' \
    --exclude=deploy-vars.yml \
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

echo "→ Загрузка архива + env на сервер..."
sftp -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$BUNDLE_DIR/id_rsa" -P "$SSH_PORT" -b - "${SSH_USER}@${SSH_HOST}" <<SFTP_EOF
put "$ARCHIVE_LOCAL" "$ARCHIVE_PATH"
put "$DEPLOY_ENV_LOCAL" "/opt/.${PROJECT_NAME}-deploy-env.sh"
SFTP_EOF

# --- 6. Логин в Registry ВРЕМЕННЫМ токеном (token идёт через stdin, не в argv) ---
# Только в CI (CI_REGISTRY+CI_JOB_TOKEN заданы). Ручной тест-запуск без них:
# авторизация в registry на сервере делается руками заранее.
if [ -n "${CI_REGISTRY:-}" ] && [ -n "${CI_JOB_TOKEN:-}" ]; then
  echo "→ docker login в $CI_REGISTRY (временный CI_JOB_TOKEN)..."
  printf '%s' "$CI_JOB_TOKEN" | \
    ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$BUNDLE_DIR/id_rsa" -p "$SSH_PORT" \
        "${SSH_USER}@${SSH_HOST}" "docker login '$CI_REGISTRY' --username gitlab-ci-token --password-stdin"
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
cat .app.secrets >> ansible/vars.yml
chmod 600 ansible/vars.yml

# --- ansible: deps (docker) + proxy (nginx-proxy) + deploy (pull образов) + healthcheck ---
cd "$PROJECT_DIR/ansible"
echo "→ ansible-playbook playbook.yml (CI-режим: pull из Registry, без сборки)"
ansible-playbook playbook.yml -e @vars.yml \
  -e "frontend_image=$FRONTEND_IMAGE backend_image=$BACKEND_IMAGE"

echo "✅ CI-деплой завершён."
REMOTE_DEPLOY

# --- 8. Логаут из Registry (токен временный) — best-effort ---
if [ "$REGISTRY_LOGGED_IN" = "1" ]; then
  ssh -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -i "$BUNDLE_DIR/id_rsa" -p "$SSH_PORT" \
      "${SSH_USER}@${SSH_HOST}" "docker logout '$CI_REGISTRY'" >/dev/null 2>&1 || true
fi

# --- 9. Финальная проверка ---
echo
echo "→ Проверка: https://$DOMAIN/api/users/count"
echo "  (сертификат может выпускаться до ~1 мин после первого запуска)"
HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "https://$DOMAIN/api/users/count" 2>/dev/null || echo "000")"
echo "  HTTP $HTTP_CODE  (ожидается 200)"
[ "$HTTP_CODE" = "200" ] || echo "⚠  Healthcheck не 200 — смотри логи на сервере: cd $PROJECT_DIR/docker && docker compose -p $PROJECT_NAME -f docker-compose.prod.yml logs"