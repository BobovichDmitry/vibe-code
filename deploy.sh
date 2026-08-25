#!/usr/bin/env bash
# =============================================================================
# deploy.sh — локальный деплой VibeSetup UI на сервер из корневого .env
# =============================================================================
# Поток:
#   1. Читает .env (SSH + DOMAIN + бренд + admin; секреты БД/JWT генерируются на сервере).
#   2. SSH по ключу через системный ssh-agent (Windows OpenSSH или POSIX).
#      Если ключа нет в агенте — ssh-add спросит passphrase ОДИН РАЗ (нативный ssh).
#   3. На сервере с нуля ставит ansible (+ python3); Docker ставит сам ansible (роль deps).
#   4. Локально собирает tar.gz исходников + deploy-env.sh (переменные из .env).
#   5. Через sftp заливает архив и env-файл на сервер, распаковывает в PROJECT_DIR.
#   6. На сервере авто-генерирует .app.secrets (db_password, jwt_secret), если нет,
#      собирает ansible/vars.yml и запускает ansible-playbook.
#      nginx-proxy + acme-companion поднимают HTTPS на DOMAIN (Let's Encrypt).
#
# Требования локально: bash (Git Bash на Windows), ssh, sftp, ssh-add, tar.
#   На Windows автоматически используется C:\Windows\System32\OpenSSH\{ssh,sftp,ssh-add}.exe
#   (работает с системным ssh-agent — ключ грузится один раз через ssh-add).
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
PROJECT_NAME="${PROJECT_NAME:-gmoreva-setup}"
PROJECT_DIR="${PROJECT_DIR:-/opt/$PROJECT_NAME}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/$PROJECT_NAME.tar.gz}"
PROXY_DIR="${PROXY_DIR:-/opt/nginx-proxy}"

echo "→ Деплой $DOMAIN на $SSH_USER@$SSH_HOST:$SSH_PORT (project: $PROJECT_NAME → $PROJECT_DIR)"

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

# --- 2. SSH-бинари: предпочтение Windows OpenSSH (System32), иначе PATH ---
SSH_BIN="ssh"; SFTP_BIN="sftp"; SSHADD_BIN="ssh-add"
if [ -x /c/Windows/System32/OpenSSH/ssh.exe ]; then
  SSH_BIN=/c/Windows/System32/OpenSSH/ssh.exe
  SFTP_BIN=/c/Windows/System32/OpenSSH/sftp.exe
  SSHADD_BIN=/c/Windows/System32/OpenSSH/ssh-add.exe
fi

# Ключ в агенте? Если нет — ssh-add спросит passphrase ОДИН РАЗ (нативный prompt).
if ! "$SSHADD_BIN" -l >/dev/null 2>&1; then
  echo "→ В ssh-agent нет ключей — добавляю $SSH_KEY (passphrase спросится один раз)..."
  "$SSHADD_BIN" "$SSH_KEY" </dev/tty || { echo "✗ Не удалось загрузить ключ $SSH_KEY" >&2; exit 1; }
else
  echo "→ ssh-agent уже содержит ключи — подключение без запроса passphrase."
fi

SSH_BASE=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -p "$SSH_PORT")
SFTP_BASE=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -P "$SSH_PORT")
SSH_CMD=("$SSH_BIN" "${SSH_BASE[@]}" "${SSH_USER}@${SSH_HOST}")

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

# --- Экранирование значений для двойных кавычек в env-файле ---
eq() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//\$/\\\$}"
  s="${s//\`/\\\`}"
  printf '"%s"' "$s"
}

# --- 4. Сборка архива исходников + deploy-env.sh локально ---
echo "→ Сборка архива исходников..."
ARCHIVE_LOCAL="/tmp/vibesetup.tar.gz"
DEPLOY_ENV_LOCAL="/tmp/vibesetup-deploy-env.sh"
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

# Файл с деплой-переменными (значения из .env). Заливается на сервер и source-ится там —
# так кавычки/пробелы не теряются при передаче через ssh (в отличие от `ssh host env VAR=...`).
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

# Windows sftp.exe не понимает MSYS-пути (/tmp/...) — конвертируем в Windows-путь.
ARCHIVE_LOCAL_WIN="$(cygpath -m "$ARCHIVE_LOCAL" 2>/dev/null || echo "$ARCHIVE_LOCAL")"
DEPLOY_ENV_WIN="$(cygpath -m "$DEPLOY_ENV_LOCAL" 2>/dev/null || echo "$DEPLOY_ENV_LOCAL")"

# --- 5. Заливка архива + deploy-env.sh через sftp ---
echo "→ Загрузка архива + env на сервер..."
"$SFTP_BIN" "${SFTP_BASE[@]}" -b - "${SSH_USER}@${SSH_HOST}" <<SFTP_EOF
put "$ARCHIVE_LOCAL_WIN" "$ARCHIVE_PATH"
put "$DEPLOY_ENV_WIN" "/opt/.${PROJECT_NAME}-deploy-env.sh"
SFTP_EOF

# --- 6. Распаковка + генерация секретов + ansible-playbook ---
echo "→ Распаковка, генерация .app.secrets, запуск ansible-playbook..."
"${SSH_CMD[@]}" env PROJECT_NAME="$PROJECT_NAME" bash -s <<'REMOTE_DEPLOY'
set -euo pipefail
# Деплой-переменные залиты через sftp (source-файл), не через ssh env —
# чтобы кавычки/пробелы в BRAND_TITLE и т.п. не терялись.
# PROJECT_NAME передан через ssh env (слаг без пробелов) — для пути к env-файлу.
# shellcheck disable=SC1091
source "/opt/.${PROJECT_NAME}-deploy-env.sh"

PROJECT_DIR="${PROJECT_DIR:-/opt/${PROJECT_NAME}}"
ARCHIVE_PATH="${ARCHIVE_PATH:-/opt/${PROJECT_NAME}.tar.gz}"

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

# --- Сборка ansible/vars.yml (vars из .env + секреты из .app.secrets) ---
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
echo "→ Логи на сервере: $SSH_BIN -p $SSH_PORT $SSH_USER@$SSH_HOST \"cd $PROJECT_DIR/docker && docker compose -p $PROJECT_NAME -f docker-compose.prod.yml logs -f app\""