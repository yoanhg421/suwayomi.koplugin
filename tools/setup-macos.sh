#!/usr/bin/env bash
# Sets up a local macOS KOReader instance to test suwayomi.koplugin against,
# without requiring Nix. Safe to re-run -- existing extracted KOReader is
# reused, the plugin is always refreshed.

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/macos"
KOREADER_APP="$BUILD_DIR/KOReader.app"
PLUGIN_DEST="$KOREADER_APP/Contents/koreader/plugins/suwayomi.koplugin"
KOREADER_ZIP="$REPO_ROOT/packages/koreader-macos-arm64.zip"

install_p7zip() {
    if ! command -v brew &>/dev/null; then
        echo "Homebrew is required to install p7zip but was not found."
        echo "Install Homebrew from https://brew.sh, then re-run this script."
        exit 1
    fi
    echo "p7zip not found. Installing via Homebrew..."
    brew install p7zip
}

check_deps() {
    if ! command -v 7za &>/dev/null && ! command -v 7zz &>/dev/null; then
        install_p7zip
    fi
}

extract_koreader() {
    if [[ -d "$KOREADER_APP" ]]; then
        echo "KOReader already extracted, skipping."
        return
    fi

    if [[ ! -f "$KOREADER_ZIP" ]]; then
        echo "Missing $KOREADER_ZIP"
        echo "Download the macOS KOReader release zip and place it there, then re-run."
        exit 1
    fi

    echo "Extracting KOReader..."
    mkdir -p "$BUILD_DIR"

    local tmp
    tmp="$(mktemp -d)"
    trap "rm -rf '$tmp'" EXIT

    unzip -q "$KOREADER_ZIP" -d "$tmp"

    local sevenz_bin
    sevenz_bin="$(command -v 7zz 2>/dev/null || command -v 7za)"

    local archive
    archive="$(find "$tmp" -name "*.7z" | head -1)"
    "$sevenz_bin" x "$archive" -o"$BUILD_DIR" -y >/dev/null

    echo "KOReader extracted to $KOREADER_APP"
}

copy_plugin_to() {
    local dest="$1"
    rm -rf "$dest"
    mkdir -p "$dest"
    rsync -a --exclude='*_spec.lua' \
        "$REPO_ROOT/_meta.lua" \
        "$REPO_ROOT/main.lua" \
        "$REPO_ROOT/suwayomi" \
        "$dest/"
    if [[ -d "$REPO_ROOT/l10n" ]]; then
        rsync -a --include='*/' --include='*.mo' --exclude='*' "$REPO_ROOT/l10n/" "$dest/l10n/"
    fi
}

install_plugin() {
    echo "Installing plugin..."

    local user_plugin_dest="$HOME/Library/Application Support/koreader/plugins/suwayomi.koplugin"

    if [[ -d "$HOME/Library/Application Support/koreader" ]]; then
        # KOReader already has a user data dir -- install only there.
        # KOReader scans both the app bundle and the user dir; installing to both
        # causes the plugin to be loaded twice.
        copy_plugin_to "$user_plugin_dest"
        rm -rf "$PLUGIN_DEST"
        echo "Plugin installed to $user_plugin_dest"
    else
        # Fresh KOReader -- no user data dir yet. Install to the app bundle so
        # KOReader finds it on first launch and populates its user dir.
        copy_plugin_to "$PLUGIN_DEST"
        echo "Plugin installed to $PLUGIN_DEST"
    fi
}

echo "=== suwayomi.koplugin macOS dev setup ==="
check_deps
extract_koreader
install_plugin
echo ""
echo "Done! Run './tools/dev-macos.sh' to launch KOReader with the plugin."
