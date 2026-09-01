#!/usr/bin/env bash
# =============================================================================
# make_deploy_bundle.sh — формирует base64-бандл для CI-деплоя (GitLab CI/CD
# Variable DEPLOY_BUNDLE_TEST / DEPLOY_BUNDLE_PRODUCTION).
#
# Содержимое бандла: tar.gz из двух файлов → base64 (одна строка):
#   id_rsa — приватный SSH-ключ БЕЗ passphrase (юзер с sudo на целевом сервере);
#   .env   — переменные деплоя, тот же формат, что у deploy.sh:
#            SSH_HOST, SSH_USER, DOMAIN, LETSENCRYPT_EMAIL, ADMIN_PASSWORD,
#            PROJECT_NAME (обязательные);
#            SSH_PORT, PROJECT_DIR, ARCHIVE_PATH, PROXY_DIR, BRAND_TITLE,
#            BRAND_FAVICON_URL, ADMIN_LOGIN (опциональные).
#            SSH_KEY указывать не нужно — ключ берётся из бандла.
#
# Использование:
#   scripts/make_deploy_bundle.sh <path/to/id_rsa> <path/to/.env>
#   → печатает base64-строку в stdout. Куда её положить:
#     1) В GitLab CI/CD Variable (DEPLOY_BUNDLE_TEST / DEPLOY_BUNDLE_PRODUCTION,
#        флаги protected + masked) — для автодеплоя из пайплайна;
#     2) В файл .ci-bundle в корне репо — для локального тест-запуска
#        docker/deploy_ci.sh (файл в .gitignore, коммитить НЕЛЬЗЯ):
#          scripts/make_deploy_bundle.sh <id_rsa> <.env> > .ci-bundle
# =============================================================================
set -euo pipefail

KEY="${1:?Usage: make_deploy_bundle.sh <id_rsa> <.env>}"
ENVF="${2:?Usage: make_deploy_bundle.sh <id_rsa> <.env>}"

[ -f "$KEY" ]  || { echo "✗ Нет файла ключа: $KEY" >&2;  exit 1; }
[ -f "$ENVF" ] || { echo "✗ Нет файла .env: $ENVF" >&2; exit 1; }

if head -c 4096 "$KEY" | grep -q "ENCRYPTED"; then
  echo "⚠  Ключ содержит passphrase — CI-ключ должен быть БЕЗ passphrase (иначе деплой упадёт)." >&2
fi

grep -q '^SSH_HOST=' "$ENVF"  || echo "⚠  В .env нет SSH_HOST" >&2
grep -q '^SSH_USER=' "$ENVF"  || echo "⚠  В .env нет SSH_USER" >&2
grep -q '^DOMAIN=' "$ENVF"    || echo "⚠  В .env нет DOMAIN" >&2
grep -q '^LETSENCRYPT_EMAIL=' "$ENVF" || echo "⚠  В .env нет LETSENCRYPT_EMAIL" >&2
grep -q '^ADMIN_PASSWORD=' "$ENVF"    || echo "⚠  В .env нет ADMIN_PASSWORD" >&2
grep -q '^PROJECT_NAME=' "$ENVF"      || echo "⚠  В .env нет PROJECT_NAME" >&2

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp "$KEY" "$TMP/id_rsa"
cp "$ENVF" "$TMP/.env"
chmod 600 "$TMP/id_rsa" "$TMP/.env"

tar -C "$TMP" -cz id_rsa .env | base64 -w0
echo >&2 ""
echo >&2 "→ Готово. Вставь строку в GitLab: Settings → CI/CD → Variables →"
echo >&2 "  DEPLOY_BUNDLE_TEST (тест) / DEPLOY_BUNDLE_PRODUCTION (прод),"
echo >&2 "  флаги Protected + Masked."