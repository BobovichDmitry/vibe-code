#!/bin/bash
# Load SSH credentials from the repo-root .env (NOT in git) and exec ssh-mcp v2 on stdio.
#
# .env (repo root) variables:
#   SSH_HOST              — домен или IP целевого сервера            (обязательно)
#   SSH_PORT              — SSH-порт (по умолчанию 22)               (опционально)
#   SSH_USER              — пользователь для входа                   (обязательно)
#
#   Auth (вариативно — ключ приоритетнее пароля):
#   SSH_KEY               — путь к приватному ключу                  (если задано → auth=key)
#                           можно с ~ : ~/.ssh/id_ed25519
#                           на Windows: C:/Users/you/.ssh/id_ed25519 (прямые слеши надёжнее)
#   SSH_KEY_PASSPHRASE    — passphrase для ключа (если он запаролен) (опционально, только с SSH_KEY)
#   SSH_PASSWORD          — пароль (используется, если SSH_KEY не задан)
#
# ssh-mcp v2: секреты только через env-переменные (не CLI). Скрипт маппит:
#   SSH_PASSWORD       → SSH_MCP_PASSWORD       (auth=password)
#   SSH_KEY_PASSPHRASE → SSH_MCP_PASSPHRASE     (auth=key, запароленный ключ)
#   путь ключа передаётся через --key (не секрет).
#
# --disableApproval: агент работает автономно (pi MCP-адаптер без elicitation);
#   policy-engine и forbidden-list всё равно действуют.
set -a
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${scriptDir}/.." || exit 1
source "./.env"
set +a

# Базовые флаги quick-start (работают и для key, и для password).
ARGS=(
  --host="$SSH_HOST"
  --port="${SSH_PORT:-22}"
  --user="$SSH_USER"
  --timeout=300000
  --maxChars=none
  --disableApproval
)

if [ -n "$SSH_KEY" ]; then
  # Auth by key (опционально — passphrase для запароленного ключа).
  ARGS+=(--key="$SSH_KEY")
  if [ -n "$SSH_KEY_PASSPHRASE" ]; then
    export SSH_MCP_PASSPHRASE="$SSH_KEY_PASSPHRASE"
  fi
  # В режиме ключа SSH_MCP_PASSWORD не выставляем, чтобы ssh-mcp не пытался паролем.
else
  # Auth by password.
  export SSH_MCP_PASSWORD="$SSH_PASSWORD"
fi

exec npx -y ssh-mcp "${ARGS[@]}"