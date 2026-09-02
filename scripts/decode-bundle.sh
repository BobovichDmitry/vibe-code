#!/usr/bin/env bash
# =============================================================================
# decode-bundle.sh — декодирует base64-бандл деплоя (DEPLOY_BUNDLE) в папку
# scripts/decoded-bundle/ для локального тест-запуска docker/deploy_ci.sh.
#
# Бандл = base64( tar.gz[ id_rsa, .env ] ) — формируется скриптом
# scripts/make_deploy_bundle.sh и хранится в GitLab CI/CD Variables
# (DEPLOY_BUNDLE_TEST / DEPLOY_BUNDLE_PRODUCTION) или в файле .ci-bundle.
#
# Использование:
#   scripts/decode-bundle.sh                        # читает ./ .ci-bundle из корня репо
#   scripts/decode-bundle.sh path/to/bundle.b64     # из указанного файла
#   DEPLOY_BUNDLE="<строка>" scripts/decode-bundle.sh   # из переменной окружения
#
# Результат (scripts/decoded-bundle/, папка в .gitignore):
#   id_rsa — приватный SSH-ключ из бандла;
#   .env   — переменные деплоя из бандла.
#
# ВНИМАНИЕ: в папке оказываются секреты (SSH-ключ, пароли) — не коммить,
# после отладки удали: rm -rf scripts/decoded-bundle
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd )"
OUT_DIR="$ROOT/scripts/decoded-bundle"

# --- 1. Источник бандла: argv > DEPLOY_BUNDLE > .ci-bundle ---
BUNDLE_FILE="${1:-}"
if [ -z "$BUNDLE_FILE" ] && [ -z "${DEPLOY_BUNDLE:-}" ]; then
  BUNDLE_FILE="$ROOT/.ci-bundle"
fi

if [ -n "$BUNDLE_FILE" ]; then
  [ -f "$BUNDLE_FILE" ] || { echo "✗ Файл бандла не найден: $BUNDLE_FILE" >&2; exit 1; }
  BUNDLE="$(tr -d '[:space:]' < "$BUNDLE_FILE")"
else
  BUNDLE="$(tr -d '[:space:]' <<<"$DEPLOY_BUNDLE")"
fi
[ -n "$BUNDLE" ] || { echo "✗ Бандл пуст — передай файл, DEPLOY_BUNDLE или клади в $ROOT/.ci-bundle" >&2; exit 1; }

# --- 2. Распаковка в scripts/decoded-bundle/ ---
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "→ Декодирование бандла в $OUT_DIR ..."
if ! printf '%s' "$BUNDLE" | base64 -d | tar -C "$OUT_DIR" -xz 2>/dev/null; then
  rm -rf "$OUT_DIR"
  echo "✗ Не удалось распаковать бандл — проверь, что это base64( tar.gz ), как делает make_deploy_bundle.sh" >&2
  exit 1
fi

# --- 3. Проверки + права ---
[ -f "$OUT_DIR/id_rsa" ] || { echo "✗ В бандле нет id_rsa" >&2; exit 1; }
[ -f "$OUT_DIR/.env" ]   || { echo "✗ В бандле нет .env" >&2;   exit 1; }
chmod 600 "$OUT_DIR/id_rsa" "$OUT_DIR/.env"

echo "✅ Готово:"
echo "   $OUT_DIR/id_rsa"
echo "   $OUT_DIR/.env"
echo
echo "Локальный тест-запуск:"
echo "  DEPLOY_BUNDLE=\"\$(cat $ROOT/.ci-bundle)\" FRONTEND_IMAGE=... BACKEND_IMAGE=... bash docker/deploy_ci.sh"
echo
echo "⚠  В папке секреты — не коммить. После отладки: rm -rf $OUT_DIR"
