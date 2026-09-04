#!/usr/bin/env bash
# =============================================================================
# deploy_local.sh — ПОЛНЫЙ цикл деплоя с ЛОКАЛЬНОЙ машины (минуя GitLab CI).
#
# Оборачивает docker/deploy_ci.sh: он умеет работать откуда угодно, ему нужны
# только sops+yq, SSH-ключ из .envs/<env>/secret.enc.yaml и образы из Registry.
#
# Использование:
#   bash deploy_local.sh                                  # production, образы :<sha HEAD>
#   DEPLOY_ENV=test bash deploy_local.sh                  # тест-стенд
#   FRONTEND_IMAGE=... BACKEND_IMAGE=... bash deploy_local.sh   # явные образы
#   IMAGE_SHA=ffccff7f bash deploy_local.sh               # образы по SHA
#
# Переменные окружения:
#   DEPLOY_ENV      — стенд (production | test; по умолчанию production)
#   IMAGE_SHA       — SHA коммита для тегов образов (по умолчанию — HEAD)
#   FRONTEND_IMAGE / BACKEND_IMAGE — полные теги образов (перекрывают IMAGE_SHA)
#   CI_JOB_TOKEN    — PAT/deploy-token для docker login в Registry на сервере
#                     (НЕ коммитить! передавать через env)
#   REGISTRY_USER   — username для docker login (по умолчанию amorev)
#   DEPLOY_SKIP_LOGIN=1 — не делать docker login (если сервер уже залогинен)
#
# Требования:
#   - .agekey в корне репо (age-ключ стенда) — расшифровка secret.enc.yaml;
#   - bash (Git Bash на Windows), ssh, curl, tar;
#   - sops/yq скачаются автоматически в .tools/ (Windows) либо берутся из PATH.
# =============================================================================
set -euo pipefail

ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$ROOT"

DEPLOY_ENV="${DEPLOY_ENV:-production}"
REGISTRY="${CI_REGISTRY:-registry.git.obvu.ru}"
PROJECT_PATH="${CI_PROJECT_PATH:-amorev/vibecode-setup}"
REGISTRY_USER="${REGISTRY_USER:-amorev}"

# --- Образы: явные FRONTEND_IMAGE/BACKEND_IMAGE > IMAGE_SHA > HEAD ---
if [ -z "${IMAGE_SHA:-}" ]; then
  IMAGE_SHA="$(git rev-parse --short=8 HEAD)"
fi
export FRONTEND_IMAGE="${FRONTEND_IMAGE:-$REGISTRY/$PROJECT_PATH/frontend:$IMAGE_SHA}"
export BACKEND_IMAGE="${BACKEND_IMAGE:-$REGISTRY/$PROJECT_PATH/backend:$IMAGE_SHA}"
export DEPLOY_ENV
export CI_REGISTRY="$REGISTRY"

echo "===== deploy_local.sh ====="
echo "  стенд:      $DEPLOY_ENV"
echo "  образы:     $FRONTEND_IMAGE"
echo "              $BACKEND_IMAGE"

# --- age-ключ ---
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  if [ -f "$ROOT/.agekey" ]; then
    export SOPS_AGE_KEY_FILE="$ROOT/.agekey"
    echo "  age-ключ:   ./.agekey"
  else
    echo "✗ Нет age-ключа: передай SOPS_AGE_KEY/SOPS_AGE_KEY_FILE или создай ./.agekey" >&2
    exit 1
  fi
fi

# --- docker login на сервере: PAT через CI_JOB_TOKEN ---
if [ "${DEPLOY_SKIP_LOGIN:-0}" != "1" ]; then
  if [ -z "${CI_JOB_TOKEN:-}" ]; then
    echo "✗ Нет CI_JOB_TOKEN (PAT для docker login в $REGISTRY)." >&2
    echo "  Передай: CI_JOB_TOKEN=glpat-... bash deploy_local.sh" >&2
    echo "  Либо DEPLOY_SKIP_LOGIN=1 — если docker login на сервере уже сделан." >&2
    exit 1
  fi
  export CI_JOB_TOKEN REGISTRY_USER
fi

# --- sops/yq: локальные бинарники (Windows → .tools/, gitignored) ---
if ! command -v sops >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1; then
  TOOLS_DIR="$ROOT/.tools"
  mkdir -p "$TOOLS_DIR"
  # Windows (MINGW/MSYS/CYGWIN) → скачиваем .exe в .tools/ и кладём в PATH.
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      dl() {
        # dl <url> <dest>: с ретраями
        local url="$1" dest="$2" i
        for i in 1 2 3; do
          if curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$dest" && [ -s "$dest" ]; then
            return 0
          fi
          echo "→ Попытка $i скачать $(basename "$dest") не удалась — retry..." >&2
          sleep 3
        done
        echo "✗ Не удалось скачать $url" >&2
        return 1
      }
      if [ ! -x "$TOOLS_DIR/sops.exe" ]; then
        echo "→ Скачиваю sops в $TOOLS_DIR/ ..."
        dl "https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.windows.amd64.exe" "$TOOLS_DIR/sops.exe"
      fi
      if [ ! -x "$TOOLS_DIR/yq.exe" ]; then
        echo "→ Скачиваю yq в $TOOLS_DIR/ ..."
        dl "https://github.com/mikefarah/yq/releases/download/v4.47.2/yq_windows_amd64.exe" "$TOOLS_DIR/yq.exe"
      fi
      export PATH="$TOOLS_DIR:$PATH"
      ;;
    *)
      # Linux/macOS: deploy_ci.sh скачает сам (ensure_sops_yq)
      ;;
  esac
fi

# --- Запуск полного цикла деплоя ---
exec bash docker/deploy_ci.sh