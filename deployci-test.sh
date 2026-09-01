#!/usr/bin/env bash
# =============================================================================
# deployci-test.sh — локальный тест-запуск CI-деплоя (без GitLab CI).
# =============================================================================
# Бандл берётся из ./.ci-bundle (см. scripts/make_deploy_bundle.sh).
# Образы — собранные пайплайном теги :master из Registry.
#
# Registry-логин: если на целевом сервере уже сделан docker login в
# registry.git.obvu.ru — запускать как есть. Иначе задай в скрипте:
#   CI_REGISTRY=registry.git.obvu.ru REGISTRY_USER=<логин> CI_JOB_TOKEN=<PAT или deploy token>
# (тогда docker login на сервере выполнит сам deploy_ci.sh).
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f .ci-bundle ] || { echo "✗ Нет .ci-bundle: scripts/make_deploy_bundle.sh <id_rsa> <.env> > .ci-bundle" >&2; exit 1; }

export FRONTEND_IMAGE="registry.git.obvu.ru/amorev/vibecode-setup/frontend:master"
export BACKEND_IMAGE="registry.git.obvu.ru/amorev/vibecode-setup/backend:master"
export DEPLOY_BUNDLE="$(cat .ci-bundle)"

# export CI_REGISTRY="registry.git.obvu.ru"
# export REGISTRY_USER="amorev"
# export CI_JOB_TOKEN="<PAT или deploy token с read_registry>"

exec bash docker/deploy_ci.sh "$@"