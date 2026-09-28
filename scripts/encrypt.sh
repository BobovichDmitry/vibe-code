#!/usr/bin/env bash
# =============================================================================
# encrypt.sh — зашифровать .envs/<env>/secret.yaml → secret.enc.yaml (sops+age).
#
# Использование: bash scripts/encrypt.sh <test|production|...>
#
# Требования:
#   - sops (https://github.com/getsops/sops);
#   - файл .envs/<env>/.agekey.public (recipient, в git) — см. docs/deployment.md.
#
# Цикл: отредактировал secret.yaml → encrypt.sh <env> → закоммить secret.enc.yaml.
# =============================================================================
set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "${scriptDir}/.." || exit 1

ENV="${1:-}"
if [ -z "$ENV" ]; then
  echo "Usage: bash scripts/encrypt.sh <env>  (напр. test, production)" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/secret.yaml" ]; then
  echo "✗ Нет файла .envs/${ENV}/secret.yaml" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/.agekey.public" ]; then
  echo "✗ Нет файла .envs/${ENV}/.agekey.public — сгенерируй пару ключей: age-keygen -o .envs/${ENV}/.agekey" >&2
  exit 1
fi

export SOPS_AGE_RECIPIENTS="$(cat ".envs/${ENV}/.agekey.public")"
sops --encrypt --input-type yaml --output-type yaml \
  --age "${SOPS_AGE_RECIPIENTS}" \
  ".envs/${ENV}/secret.yaml" > ".envs/${ENV}/secret.enc.yaml"

echo "→ Зашифровано: .envs/${ENV}/secret.enc.yaml (не забудь закоммитить)"
