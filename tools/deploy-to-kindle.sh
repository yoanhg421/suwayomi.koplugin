#!/usr/bin/env bash
set -euo pipefail

HOST="${REMOTE_KOREADER_HOST}"
PORT="${REMOTE_KOREADER_SSH_PORT:-2222}"

if [[ -z "$HOST" ]]; then
  echo "Set REMOTE_KOREADER_HOST environment variable first."
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_PATH="/mnt/us/koreader/plugins/suwayomi.koplugin"

echo "Deploying suwayomi.koplugin runtime payload to $HOST:$PORT..."

# Remove existing plugin files on the device and copy new ones via tar over ssh.
sshpass -p '' ssh -p "$PORT" -o StrictHostKeyChecking=no "root@$HOST" "rm -rf ${REMOTE_PATH}"

# Only the runtime payload ships: _meta.lua, main.lua, suwayomi/, and compiled
# l10n/*/suwayomi.mo catalogs when present. No specs, docs, or CI files.
(
  cd "$REPO_ROOT"
  tar -czf - \
    --exclude='*_spec.lua' \
    _meta.lua main.lua suwayomi \
    $( [[ -d l10n ]] && find l10n -name '*.mo' )
) | sshpass -p '' ssh -p "$PORT" -o StrictHostKeyChecking=no "root@$HOST" "mkdir -p ${REMOTE_PATH} && tar -xzf - -C ${REMOTE_PATH}"

echo "Plugin deployed. Please restart KOReader on the Kindle."
