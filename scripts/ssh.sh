#!/bin/bash
# Load SSH credentials from the repo-root .env (NOT in git) and exec ssh-mcp v2 on stdio.
# .env must live at the repo root and contain: SSH_HOST, SSH_PORT, SSH_USER, SSH_PASSWORD
# SSH_HOST can be a domain or an IP address.
#
# ssh-mcp v2: password via SSH_MCP_PASSWORD env var (NOT --password CLI flag).
# --disableApproval: skip the human-in-the-loop approval gate so the agent can run
#   autonomously (pi MCP adapter has no elicitation). The policy engine + forbidden
#   list still apply. Remove this flag if you want interactive approval prompts.
set -a
scriptDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "${scriptDir}/.." || exit 1
source "./.env"
set +a

# Map generic .env var to the ssh-mcp v2 credential env var.
export SSH_MCP_PASSWORD="$SSH_PASSWORD"

exec npx -y ssh-mcp \
        --host="$SSH_HOST" \
        --port="$SSH_PORT" \
        --user="$SSH_USER" \
        --timeout=300000 \
        --maxChars=none \
        --disableApproval