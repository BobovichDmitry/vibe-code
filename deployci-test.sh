#!/usr/bin/env bash
# =============================================================================
# deployci-test.sh — локальный тест-запуск CI-деплоя (без GitLab CI).
# =============================================================================
# Ключ расшифровки берётся из .envs/<env>/.agekey (per-env, gitignored,
# создаётся age-keygen) или из env SOPS_AGE_KEY. Образы — собранные пайплайном теги :master из Registry.
#
# Registry-логин: если на целевом сервере уже сделан docker login в
# registry.git.obvu.ru — запускать как есть. Иначе задай в скрипте:
#   CI_REGISTRY=registry.git.obvu.ru REGISTRY_USER=<логин> CI_JOB_TOKEN=<PAT или deploy token>
# (тогда docker login на сервере выполнит сам deploy_ci.sh).
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

export DEPLOY_ENV="${DEPLOY_ENV:-test}"

if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ ! -f ".envs/$DEPLOY_ENV/.agekey" ]; then
  echo "✗ Нет ключа расшифровки: создай .envs/$DEPLOY_ENV/.agekey (age-keygen -o .envs/$DEPLOY_ENV/.agekey) или задай SOPS_AGE_KEY" >&2
  exit 1
fi
export FRONTEND_IMAGE="registry.git.obvu.ru/amorev/vibecode-setup/frontend:master"
export BACKEND_IMAGE="registry.git.obvu.ru/amorev/vibecode-setup/backend:master"

# export CI_REGISTRY="registry.git.obvu.ru"
# export REGISTRY_USER="amorev"
# export CI_JOB_TOKEN="<PAT или deploy token с read_registry>"

exec bash docker/deploy_ci.sh "$@"
