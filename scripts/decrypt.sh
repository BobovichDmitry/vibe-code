#!/usr/bin/env bash
# =============================================================================
# decrypt.sh — расшифровать .envs/<env>/secret.enc.yaml → secret.yaml (sops+age).
#
# Использование: bash scripts/decrypt.sh <test|production|...>
#
# Требуется приватный ключ: env SOPS_AGE_KEY (содержимое ключа), SOPS_AGE_KEY_FILE
# или файл .agekey в корне репо (gitignored).
# =============================================================================
set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "${scriptDir}/.." || exit 1

ENV="${1:-}"
if [ -z "$ENV" ]; then
  echo "Usage: bash scripts/decrypt.sh <env>  (напр. test, production)" >&2
  exit 1
fi
if [ ! -f ".envs/${ENV}/secret.enc.yaml" ]; then
  echo "✗ Нет файла .envs/${ENV}/secret.enc.yaml" >&2
  exit 1
fi

# Приватный ключ: env SOPS_AGE_KEY > SOPS_AGE_KEY_FILE > ./.agekey
if [ -z "${SOPS_AGE_KEY:-}" ] && [ -z "${SOPS_AGE_KEY_FILE:-}" ]; then
  if [ -f "./.agekey" ]; then
    export SOPS_AGE_KEY_FILE="./.agekey"
  else
    echo "✗ Нет ключа: задай SOPS_AGE_KEY (или SOPS_AGE_KEY_FILE, или создай ./.agekey)" >&2
    exit 1
  fi
fi

sops -d --input-type yaml --output-type yaml \
  ".envs/${ENV}/secret.enc.yaml" > ".envs/${ENV}/secret.yaml"

echo "→ Расшифровано: .envs/${ENV}/secret.yaml (файл в .gitignore, не коммитить)"
