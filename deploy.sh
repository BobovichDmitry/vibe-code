#!/usr/bin/env bash
# =============================================================================
# deploy.sh — локальный деплой VibeSetup UI на сервер из корневого .env
# =============================================================================
# Поток:
#   1. Читает .env (SSH + DOMAIN + бренд + admin; секреты БД/JWT генерируются на сервере).
#   2. SSH по ключу (passphrase спрашивается ОДИН РАЗ через ssh-agent).
#   3. На сервере с нуля ставит ansible (+ python3); Docker ставит сам ansible (роль deps).
#   4. Локально собирает tar.gz исходников (без .env / node_modules / dist / .git ...).
#   5. Через sftp заливает архив на сервер и распаковывает в PROJECT_DIR.
#   6. На сервере авто-генерирует .app.secrets (db_password, jwt_secret), если нет.
#   7. Собирает ansible/vars.yml и запускает ansible-playbook (proxy + deploy + healthcheck).
#      nginx-proxy + acme-companion поднимают HTTPS на DOMAIN (Let's Encrypt).
#
# Требования локально: bash (Git Bash на Windows), ssh, sftp, ssh-agent, ssh-add, tar.
# Требования в .env: SSH_HOST, SSH_USER, SSH_KEY, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD.
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$ROOT"

# --- 1. .env ---
if [ ! -f .env ]; then
  echo "✗ Нет .env в корне. Выполните: cp .env.example .env — и заполните." >&2
  exit 1
fi
set -a; source ./.env; set +a

: "${SSH_HOST:?✗ SSH_HOST не задан в .env}"
: "${SSH_USER:?✗ SSH_USER не задан в .env}"
: "${DOMAIN:?✗ DOMAIN не задан в .env}"
: "${LETSENCRYPT_EMAIL:?✗ LETSENCRYPT_EMAIL не задан в .env}"
: "${ADMIN_PASSWORD:?✗ ADMIN_PASSWORD не задан в .env}"
: "${SSH_KEY:?✗ deploy.sh работает по ключу — задайте SSH_KEY в .env}"
SSH_PORT="${SSH_PORT:-22}"
ADMIN_LOGIN="${ADMIN_LOGIN:-admin}"
BRAND_TITLE="${BRAND_TITLE:-VibeSetup UI}"
BRAND_FAVICON_URL="${BRAND_FAVICON_URL:-/favicon.svg}"
PROJECT_DIR="${PROJECT_DIR:-/opt/vibesetup}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/vibesetup.tar.gz}"
PROXY_DIR="${PROXY_DIR:-/opt/nginx-proxy}"

echo "→ Деплой $DOMAIN на $SSH_USER@$SSH_HOST:$SSH_PORT (project: $PROJECT_DIR)"

# --- Best-effort проверка DNS: DOMAIN должен указывать на SSH_HOST ---
PY="$(command -v python || command -v python3 || true)"
if [ -n "$PY" ]; then
  RESOLVED="$("$PY" -c "import socket,sys
try:
    print(socket.gethostbyname(sys.argv[1]))
except Exception:
    print('')
" "$DOMAIN" 2>/dev/null || true)"
  if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "$SSH_HOST" ]; then
    echo "⚠  ВНИМАНИЕ: $DOMAIN резолвится в '$RESOLVED', а не в '$SSH_HOST'." >&2
    echo "   Let's Encrypt не выпустит сертификат — поправьте DNS A-запись." >&2
    echo "   Продолжить? (y/N)"; read -r ANS </dev/tty
    [ "$ANS" = "y" ] || { echo "Остановлено."; exit 1; }
  elif [ -n "$RESOLVED" ]; then
    echo "→ DNS OK: $DOMAIN → $RESOLVED"
  fi
fi

# --- 2. SSH-агент: passphrase ОДИН РАЗ ---
AGENT_STARTED=0
if [ -z "${SSH_AUTH_SOCK:-}" ] || ! ssh-add -l >/dev/null 2>&1; then
  eval "$(ssh-agent -s)" >/dev/null
  AGENT_STARTED=1
fi
# ssh-add добавит ключ; если ключ уже в агенте — просто пропустит.
if ! ssh-add -l 2>/dev/null | grep -q .; then
  echo "→ Добавляю ключ в ssh-agent (passphrase спросится один раз)..."
  ssh-add "$SSH_KEY" || { echo "✗ Не удалось загрузить ключ $SSH_KEY" >&2; exit 1; }
fi
cleanup() {
  if [ "$AGENT_STARTED" = "1" ] && [ -n "${SSH_AGENT_PID:-}" ]; then
    kill "$SSH_AGENT_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

SSH_BASE=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p "$SSH_PORT")
SSH_CMD=(ssh "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}")
SFTP_CMD=(sftp "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}")

# --- 3. Установка ansible на сервере (с нуля) ---
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

# --- 4. Сборка архива исходников локально ---
echo "→ Сборка архива исходников..."
rm -f /tmp/vibesetup.tar.gz
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
    -czf /tmp/vibesetup.tar.gz -C "$ROOT" .
echo "   архив: $(du -h /tmp/vibesetup.tar.gz | cut -f1)"

# --- 5. Заливка архива через sftp ---
echo "→ Загрузка архива на сервер ($ARCHIVE_PATH)..."
"${SFTP_CMD[@]}" -b - <<SFTP_EOF
put /tmp/vibesetup.tar.gz $ARCHIVE_PATH
SFTP_EOF

# --- 6. Распаковка + генерация секретов + ansible-playbook ---
echo "→ Распаковка, генерация .app.secrets, запуск ansible-playbook..."
"${SSH_CMD[@]}" env \
  DOMAIN="$DOMAIN" \
  LETSENCRYPT_EMAIL="$LETSENCRYPT_EMAIL" \
  BRAND_TITLE="$BRAND_TITLE" \
  BRAND_FAVICON_URL="$BRAND_FAVICON_URL" \
  ADMIN_LOGIN="$ADMIN_LOGIN" \
  ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  PROJECT_DIR="$PROJECT_DIR" \
  ARCHIVE_PATH="$ARCHIVE_PATH" \
  PROXY_DIR="$PROXY_DIR" \
  SSH_HOST="$SSH_HOST" \
  bash -s <<'REMOTE_DEPLOY'
set -euo pipefail
PROJECT_DIR="$PROJECT_DIR"; ARCHIVE_PATH="$ARCHIVE_PATH"; PROXY_DIR="$PROXY_DIR"

mkdir -p "$PROJECT_DIR"
echo "→ Распаковка архива в $PROJECT_DIR..."
tar -xzf "$ARCHIVE_PATH" -C "$PROJECT_DIR"
cd "$PROJECT_DIR"

# --- Авто-генерация .app.secrets (db_password, jwt_secret), если нет ---
if [ ! -f .app.secrets ]; then
  DBPW="$(openssl rand -hex 18)"
  JWT="$(openssl rand -hex 32)"
  umask 077
  printf 'db_password: "%s"\njwt_secret: "%s"\n' "$DBPW" "$JWT" > .app.secrets
  echo "→ Сгенерирован $PROJECT_DIR/.app.secrets (db_password, jwt_secret)"
else
  echo "→ .app.secrets уже есть — переиспользуем (секреты не перевыпускаются)"
fi

# --- Сборка ansible/vars.yml (неперсиональные vars + секреты из .app.secrets) ---
umask 077
cat > ansible/vars.yml <<YML
server_ip: "$SSH_HOST"
domain: "$DOMAIN"
letsencrypt_email: "$LETSENCRYPT_EMAIL"
project_dir: "$PROJECT_DIR"
archive_path: "$ARCHIVE_PATH"
proxy_dir: "$PROXY_DIR"
brand_title: "$BRAND_TITLE"
brand_favicon_url: "$BRAND_FAVICON_URL"
admin_login: "$ADMIN_LOGIN"
admin_password: "$ADMIN_PASSWORD"
db_username: "vibesetup"
db_name: "vibesetup_db"
YML
cat .app.secrets >> ansible/vars.yml
chmod 600 ansible/vars.yml

# --- Запуск ansible (deps: Docker, proxy: nginx-proxy+acme, deploy: app, healthcheck) ---
cd "$PROJECT_DIR/ansible"
echo "→ ansible-playbook playbook.yml -e @vars.yml"
ansible-playbook playbook.yml -e @vars.yml

echo "✅ Деплой завершён."
REMOTE_DEPLOY

# --- 7. Финальная проверка ---
echo
echo "→ Проверка: https://$DOMAIN/api/users/count"
echo "  (сертификат может выпускаться до ~1 мин после первого запуска)"
HTTP_CODE="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 30 "https://$DOMAIN/api/users/count" 2>/dev/null || echo "000")"
echo "  HTTP $HTTP_CODE  (ожидается 200)"
echo "→ Логи на сервере: ssh ${SSH_USER}@${SSH_HOST} 'cd $PROJECT_DIR/docker && docker compose -f docker-compose.prod.yml logs -f app'"