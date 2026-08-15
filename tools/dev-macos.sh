#!/usr/bin/env bash
# Launches KOReader with suwayomi.koplugin installed for local testing.
#
# suwayomi.koplugin is pure Lua and talks directly to a Suwayomi server over
# HTTP, so there is no backend process to build or start -- this script only
# refreshes the plugin files and launches KOReader.
#
# Run setup-macos.sh first if you haven't already.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOREADER_BIN="$REPO_ROOT/build/macos/KOReader.app/Contents/MacOS/koreader"
# setup-macos.sh installs the plugin to the user data dir when it exists (to avoid
# double-loading), so resolve the effective plugin dir the same way.
if [[ -d "$HOME/Library/Application Support/koreader" ]]; then
    PLUGIN_DIR="$HOME/Library/Application Support/koreader/plugins/suwayomi.koplugin"
else
    PLUGIN_DIR="$REPO_ROOT/build/macos/KOReader.app/Contents/koreader/plugins/suwayomi.koplugin"
fi

if [[ ! -x "$KOREADER_BIN" ]]; then
    echo "KOReader not found. Run './tools/setup-macos.sh' first."
    exit 1
fi

# Reinstall the plugin on every launch so frontend changes are picked up immediately.
mkdir -p "$PLUGIN_DIR"
rsync -a --delete --exclude='*_spec.lua' \
    "$REPO_ROOT/_meta.lua" \
    "$REPO_ROOT/main.lua" \
    "$REPO_ROOT/suwayomi" \
    "$PLUGIN_DIR/"
if [[ -d "$REPO_ROOT/l10n" ]]; then
    rsync -a --include='*/' --include='*.mo' --exclude='*' "$REPO_ROOT/l10n/" "$PLUGIN_DIR/l10n/"
fi

exec "$KOREADER_BIN" "$HOME"
