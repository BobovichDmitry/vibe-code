#!/usr/bin/env bash
# =============================================================================
# deploy_0downtime.sh — деплой без простоя (blue-green переключение слотов).
#
# Запускается НА СЕРВЕРЕ из каталога docker/ (ansible-роль app вызывает его
# вместо прямого `docker compose up -d`). Также подходит для ручного запуска:
#
#   ./deploy_0downtime.sh <project_name> --build   # сборка образов на сервере (deploy.sh)
#   ./deploy_0downtime.sh <project_name> --pull   # образы уже в Registry (CI)
#
# Схема (см. docker-compose.prod.yml):
#   nginx-proxy → edge-nginx → frontend-<slot> ← backend-<slot> (слот целиком)
#
# Алгоритм:
#   1. Определяет активный слот (docker/.active-slot; по умолчанию blue).
#   2. Собирает/пуллит образы STANDBY-слота.
#   3. Поднимает postgres + edge-nginx (идемпотентно; на первом деплое — bootstrap).
#   4. Поднимает standby-слот, ждёт healthcheck backend/frontend (/api/health).
#   5. Переключает upstream edge-nginx на новый слот (nginx -s reload, без простоя).
#   6. Верифицирует /api/health через edge-nginx (полный путь edge→frontend→backend).
#   7. Останавливает старый слот (с задержкой OLD_SLOT_STOP_DELAY).
#   Любая ошибка → rollback upstream на активный слот + reload, старый слот жив.
#
# Telegram-уведомления: если в docker/env заданы BOT_TOKEN и
# TELEGRAM_NOTIFY_CHAT (опционально TELEGRAM_NOTIFY_TOPIC) — присылает
# start-сообщение и редактирует его в итог (Active slot / время / результат).
# Не заданы — уведомления молча пропускаются.
# =============================================================================
set -euo pipefail

MODE="pull"
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build) MODE="build" ;;
    --pull)  MODE="pull" ;;
    -*) echo "✗ Неизвестный флаг: $1" >&2; exit 1 ;;
    *)  PROJECT="$1" ;;
  esac
  shift
done
[ -n "$PROJECT" ] || { echo "Usage: $0 <project_name> --build|--pull" >&2; exit 1; }

cd "$(dirname "${BASH_SOURCE[0]}")"

COMPOSE="docker compose -p $PROJECT -f docker-compose.prod.yml"
STATE_FILE="./.active-slot"
UPSTREAM_FILE="./nginx/runtime/upstream-frontend.conf"
OLD_SLOT_STOP_DELAY="${OLD_SLOT_STOP_DELAY:-10}"
HEALTH_RETRIES=60
HEALTH_SLEEP=2

# --- Telegram ---
env_val() { grep -m1 -E "^$1=" ./env 2>/dev/null | cut -d= -f2- || true; }
BOT_TOKEN="$(env_val BOT_TOKEN)"
NOTIFY_CHAT="$(env_val TELEGRAM_NOTIFY_CHAT)"
NOTIFY_TOPIC="$(env_val TELEGRAM_NOTIFY_TOPIC)"
CAN_SEND=0
if [ -n "$BOT_TOKEN" ] && [ -n "$NOTIFY_CHAT" ]; then CAN_SEND=1; fi

tg_send() {
  [ "$CAN_SEND" = 1 ] || return 0
  # tg_send <text> [reply_to] — выводит message_id (или пустую строку)
  local msg_id
  msg_id=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$NOTIFY_CHAT" \
    ${NOTIFY_TOPIC:+-d message_thread_id="$NOTIFY_TOPIC"} \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true \
    --data-urlencode "text=$1" 2>/dev/null) || return 0
  echo "$msg_id" | grep -o '"message_id":[0-9]*' | cut -d: -f2 || true
}

tg_edit() {
  # tg_edit <message_id> <text>
  [ "$CAN_SEND" = 1 ] || return 0
  [ -n "$1" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/editMessageText" \
    -d chat_id="$NOTIFY_CHAT" \
    ${NOTIFY_TOPIC:+-d message_thread_id="$NOTIFY_TOPIC"} \
    -d message_id="$1" \
    -d parse_mode="HTML" \
    -d disable_web_page_preview=true \
    --data-urlencode "text=$2" >/dev/null 2>&1 || true
}

tg_react() {
  # tg_react <message_id> <emoji>
  [ "$CAN_SEND" = 1 ] || return 0
  [ -n "$1" ] || return 0
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/setMessageReaction" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\": \"$NOTIFY_CHAT\", \"message_id\": $1, \"reaction\": [{\"type\":\"emoji\",\"emoji\":\"$2\"}]}" \
    >/dev/null 2>&1 || true
}

START_TS="$(date +%s)"
TEXT="<b>Deploy $PROJECT</b>"
TG_MSG_ID="$(tg_send "$TEXT")"

# --- Слоты ---
write_upstream() {
  # write_upstream <blue|green>
  cat > "$UPSTREAM_FILE" <<EOF
# Управляется скриптом деплоя docker/deploy_0downtime.sh (blue/green).
# НЕ редактируйте вручную — переключается при каждом деплое.
upstream app_frontend {
    server frontend-$1:3000;
    keepalive 64;
}
EOF
}

ACTIVE_SLOT="blue"
if [ -f "$STATE_FILE" ]; then ACTIVE_SLOT="$(tr -d '[:space:]' < "$STATE_FILE")"; fi
case "$ACTIVE_SLOT" in
  blue)  STANDBY_SLOT="green" ;;
  green) STANDBY_SLOT="blue" ;;
  *) echo "⚠  Некорректное значение $STATE_FILE ('$ACTIVE_SLOT') — считаю активным blue"; ACTIVE_SLOT="blue"; STANDBY_SLOT="green" ;;
esac
# Первый деплой на пустом сервере: оба слота ещё не поднимались
BOOTSTRAP=0
[ -f "$STATE_FILE" ] || BOOTSTRAP=1

echo "→ Активный слот:   $ACTIVE_SLOT${BOOTSTRAP:+ (bootstrap — файла $STATE_FILE нет)}"
echo "→ Новый слот:     $STANDBY_SLOT (режим: $MODE)"

set +e
fail_deploy() {
  echo "✗ $1" >&2
  # Rollback: возвращаем upstream на работающий слот. На bootstrap 'активного'
  # слота нет (blue не поднимался) — пишем standby, который реально жив.
  if [ "$BOOTSTRAP" = "1" ]; then ROLLBACK_SLOT="$STANDBY_SLOT"; else ROLLBACK_SLOT="$ACTIVE_SLOT"; fi
  echo "→ Rollback: возвращаю upstream на слот $ROLLBACK_SLOT" >&2
  write_upstream "$ROLLBACK_SLOT"
  $COMPOSE exec -T edge-nginx nginx -t >/dev/null 2>&1 && \
    $COMPOSE exec -T edge-nginx nginx -s reload >/dev/null 2>&1 || true
  DURATION_MIN=$(( ($(date +%s) - START_TS) / 60 ))
  tg_edit "$TG_MSG_ID" "${TEXT}

<b>❌ Деплой FAILED</b>
<code>$1</code>

<i>Через ${DURATION_MIN} мин</i>·Active slot: $ACTIVE_SLOT (не менялся)"
  exit 1
}
set -e

wait_health() {
  # wait_health <service> — docker healthcheck статуса healthy
  local service="$1" i cid status
  for i in $(seq 1 "$HEALTH_RETRIES"); do
    cid="$($COMPOSE ps -q "$service" 2>/dev/null | head -n 1)"
    if [ -n "$cid" ]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
      if [ "$status" = "healthy" ]; then
        echo "→ $service: healthy"
        return 0
      fi
    fi
    sleep "$HEALTH_SLEEP"
  done
  echo "✗ $service не стал healthy за $((HEALTH_RETRIES * HEALTH_SLEEP))с (status: ${status:-нет контейнера})" >&2
  return 1
}

# --- 1. Образы standby-слота ---
if [ "$MODE" = "build" ]; then
  echo "→ Сборка образов слота $STANDBY_SLOT на сервере..."
  $COMPOSE build "frontend-$STANDBY_SLOT" "backend-$STANDBY_SLOT" || fail_deploy "Не собрались образы слота $STANDBY_SLOT"
else
  echo "→ Pull образов слота $STANDBY_SLOT из Registry..."
  $COMPOSE pull "frontend-$STANDBY_SLOT" "backend-$STANDBY_SLOT" || fail_deploy "Не удалось сделать pull образов слота $STANDBY_SLOT"
fi

# --- 2. Общая инфраструктура: postgres (идемпотентно) ---
echo "→ Postgres (up -d)..."
$COMPOSE up -d postgres || fail_deploy "Не поднялся postgres"
wait_health postgres || fail_deploy "Postgres не стал healthy"

# --- 3. Поднимаем standby-слот ---
echo "→ Поднимаю слот $STANDBY_SLOT (backend-$STANDBY_SLOT + frontend-$STANDBY_SLOT)..."
$COMPOSE up -d "backend-$STANDBY_SLOT" "frontend-$STANDBY_SLOT" || fail_deploy "Не поднялись сервисы слота $STANDBY_SLOT"
wait_health "backend-$STANDBY_SLOT" || fail_deploy "backend-$STANDBY_SLOT не прошёл healthcheck"
wait_health "frontend-$STANDBY_SLOT" || fail_deploy "frontend-$STANDBY_SLOT не прошёл healthcheck"

# --- 4. Переключение upstream (без простоя) ---
if [ "$BOOTSTRAP" = "1" ]; then
  # Bootstrap: upstream-файл из репо указывает на blue, а blue может быть не
  # поднят — edge-nginx стартовал бы с нерезолвящимся upstream и ушёл в
  # рестарт-луп. Переключаем upstream на реально поднимаемый слот ДО старта edge.
  echo "→ Bootstrap: upstream → слот $STANDBY_SLOT (до старта edge-nginx)..."
  write_upstream "$STANDBY_SLOT"
  echo "→ Edge-nginx (первый старт, --force-recreate: контейнер может остаться
     в рестарт-лупе после неудачного bootstrap, up -d его не пересоздаёт)..."
  $COMPOSE up -d --force-recreate edge-nginx || fail_deploy "Не поднялся edge-nginx (bootstrap)"
else
  # Обычный деплой: edge уже работает на активном слоте — просто переключаем.
  echo "→ Переключаю upstream edge-nginx на слот $STANDBY_SLOT..."
  write_upstream "$STANDBY_SLOT"
fi
# exec может попасть в рестарт-луп контейнера (bootstrap): ретраи.
NGINX_T_OK=0
for _try in 1 2 3 4 5 6 7 8 9 10; do
  if $COMPOSE exec -T edge-nginx nginx -t >/dev/null 2>&1; then NGINX_T_OK=1; break; fi
  sleep 2
done
[ "$NGINX_T_OK" = "1" ] || fail_deploy "nginx -t упал после переключения upstream"
NGINX_RELOAD_OK=0
for _try in 1 2 3 4 5 6; do
  if $COMPOSE exec -T edge-nginx nginx -s reload >/dev/null 2>&1; then NGINX_RELOAD_OK=1; break; fi
  sleep 5
done
[ "$NGINX_RELOAD_OK" = "1" ] || fail_deploy "nginx -s reload упал после переключения upstream"

# --- 5. Верификация полного пути edge-nginx → frontend → backend ---
for i in $(seq 1 10); do
  if $COMPOSE exec -T edge-nginx wget --no-verbose --tries=1 --spider http://127.0.0.1/api/health >/dev/null 2>&1; then
    echo "→ Верификация нового слота: OK (/api/health через edge-nginx)"
    break
  fi
  if [ "$i" = "10" ]; then fail_deploy "Новый слот $STANDBY_SLOT не прошёл верификацию через edge-nginx"; fi
  sleep 2
done

# --- 6. Фиксируем состояние ---
echo "$STANDBY_SLOT" > "$STATE_FILE"

# --- 7. Останавливаем старый слот ---
if [ "$BOOTSTRAP" = "1" ]; then
  echo "→ Bootstrap: старый слот не останавливаю"
else
  if [ "$OLD_SLOT_STOP_DELAY" -gt 0 ] 2>/dev/null; then
    echo "→ Пауза ${OLD_SLOT_STOP_DELAY}с перед остановкой старого слота $ACTIVE_SLOT..."
    sleep "$OLD_SLOT_STOP_DELAY"
  fi
  echo "→ Останавливаю слот $ACTIVE_SLOT..."
  $COMPOSE stop "backend-$ACTIVE_SLOT" "frontend-$ACTIVE_SLOT" || fail_deploy "Не удалось остановить старый слот $ACTIVE_SLOT"
fi

# --- 8. Легаси-контейнеры миграции на blue-green ---
# Контейнеры frontend/backend старой (до-blue-green) схемы: nginx-proxy может
# продолжать маршрутизировать домен на них (двойной VIRTUAL_HOST). best-effort.
for legacy in frontend backend; do
  ids="$(docker ps -aq --filter "label=com.docker.compose.project=$PROJECT" \
                     --filter "label=com.docker.compose.service=$legacy")"
  if [ -n "$ids" ]; then
    echo "→ Удаляю легаси-контейнер '$legacy' (старая схема, до blue-green)..."
    docker rm -f $ids >/dev/null 2>&1 || true
  fi
done

END_TS=$(date +%s)
DURATION_MIN=$(( (END_TS - START_TS) / 60 ))
FINISH_TIME="$(date +%H:%M:%S)"

tg_react "$TG_MSG_ID" "👍"
tg_edit "$TG_MSG_ID" "${TEXT}

<b>Active slot:</b> ${STANDBY_SLOT}
<b>Stopped slot:</b> ${ACTIVE_SLOT}
<b>Finish:</b> ${FINISH_TIME} (${DURATION_MIN} мин)"

echo "✅ Деплой без простоя завершён. Активный слот: $STANDBY_SLOT"
