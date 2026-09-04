#!/usr/bin/env bash
# =============================================================================
# lint-remote-scripts.sh — синтаксическая проверка remote-скриптов в heredoc'ах.
#
# deploy.sh / docker/deploy_ci.sh отправляют на сервер скрипты через
# `ssh ... bash -s <<'REMOTE_...'`. Внешний `bash -n` НЕ проверяет содержимое
# heredoc (это просто текст) — из-за этого сломанный remote-скрипт (напр.
# yml_str с несбалансированными кавычками) ловится только падением деплоя
# НА СЕРВЕРЕ (см. docs: setup-feedback 2.1).
#
# Скрипт вырезает каждый heredoc-блок `<<'NAME' ... NAME` и гоняет `bash -n`
# на его содержимом. Ненулевой exit = есть синтаксические ошибки.
#
# Использование: bash scripts/lint-remote-scripts.sh [файлы...]
# (по умолчанию: deploy.sh docker/deploy_ci.sh)
# Запускается в CI (джоба lint:remote-scripts) — gawk обязателен.
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/.."
cd "$ROOT"

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  FILES=(deploy.sh docker/deploy_ci.sh)
fi

TMP_LINT="$(mktemp -d)"
trap 'rm -rf "$TMP_LINT"' EXIT

for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "✗ Нет файла $f" >&2; exit 1; }
  base="$(basename "$f" | tr '.' '_')"
  # Вырезаем содержимое quoted-heredoc'ов: строки между `<<'NAME'` и строкой `NAME`.
  # gawk-only (match с массивом) — есть в Git Bash и на Linux-раннере.
  awk -v outdir="$TMP_LINT" -v base="$base" '
    !inh && match($0, /<+'"'"'([A-Z_][A-Z_0-9]*)'"'"'/, m) {
      name = m[1]; inh = 1; out = outdir "/" base "__" name ".sh"; next
    }
    inh && $0 == name { inh = 0; next }
    inh { print > out }
  ' "$f"
done

echo "→ bash -n на remote-скриптах из heredoc'ов:"
FAIL=0
shopt -s nullglob
for s in "$TMP_LINT"/*.sh; do
  if bash -n "$s" 2>"$TMP_LINT/err.txt"; then
    echo "  OK: $(basename "$s")"
  else
    echo "  ✗ $(basename "$s"):" >&2
    sed 's/^/    /' "$TMP_LINT/err.txt" >&2
    FAIL=1
  fi
done

if [ "$FAIL" = "0" ]; then
  echo "✅ Все remote-скрипты синтаксически валидны"
else
  echo "✗ Есть синтаксические ошибки в remote-скриптах (см. выше)" >&2
fi
exit "$FAIL"