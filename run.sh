#!/bin/bash
# IsolynV2.0 — build + wrap in minimal .app bundle + launch
# Usage: ./run.sh [--release]
#
# Why this exists: SwiftPM executables don't produce .app bundles, and macOS
# SwiftUI requires Bundle.main.bundleIdentifier to create windows. This
# script wraps the compiled binary in a minimal .app structure so the app
# launches correctly. For Xcode debugging, open Package.swift directly.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(pwd)"

CONFIG="debug"
[[ "${1:-}" == "--release" ]] && CONFIG="release"

echo "🔨 Building ($CONFIG)..."
swift build -c "$CONFIG" 2>&1 | tail -1

BINARY=".build/$([ "$CONFIG" = "debug" ] && echo "debug" || echo "release")/IsolynV2.0"
[ -f "$BINARY" ] || { echo "❌ binary not found at $BINARY"; exit 1; }

APP="build/IsolynV2.0.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/IsolynV2.0"
cp "Assets/Isolyn.icns" "$APP/Contents/Resources/Isolyn.icns"

# Stage the lab runtime outside the checkout. The app must never read the
# sources under ~/Desktop: macOS treats that as a protected folder, and because
# this bundle is ad-hoc signed on every build, a granted permission never
# survives the next rebuild. Application Support is not protected, and keeping
# the runtime out of the bundle also avoids codesign rejecting nested binaries
# that carry com.apple.provenance.
LAB="$HOME/Library/Application Support/IsolynV2.0/Lab"
rm -rf "$LAB"
mkdir -p "$LAB/scripts" "$LAB/lab/src" "$LAB/lab/configs" "$LAB/tools/selfplay/build"
cp "$ROOT/scripts/lab" "$LAB/scripts/lab"
cp -R "$ROOT/lab/src/isolyn_lab" "$LAB/lab/src/isolyn_lab"
cp -R "$ROOT/lab/configs/." "$LAB/lab/configs/"
if [ -f "$ROOT/tools/selfplay/build/selfplay" ]; then
    cp "$ROOT/tools/selfplay/build/selfplay" "$LAB/tools/selfplay/build/selfplay"
fi
chmod +x "$LAB/scripts/lab" 2>/dev/null || true
chmod +x "$LAB/tools/selfplay/build/selfplay" 2>/dev/null || true
# Python bytecode the interpreter writes there is fine; nothing else is expected.
echo "📦 Staged the lab runtime in Application Support"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.isolyn.app</string>
<key>CFBundleName</key><string>IsolynV2.0</string>
<key>CFBundleIconFile</key><string>Isolyn</string>
<key>CFBundleExecutable</key><string>IsolynV2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict></plist>
PLIST

# Stamp the build into the bundle so the running window can be identified.
BUILD_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
/usr/libexec/PlistBuddy -c "Delete :IsolynBuild" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :IsolynBuild string $BUILD_HASH" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true

echo "🚀 Launching IsolynV2.0 ($BUILD_HASH)…"
# A copied SwiftPM executable can carry a signature that macOS rejects once it
# is wrapped in a fresh .app (the launch dies with "Code Signature Invalid").
# Clear Finder/resource xattrs and ad-hoc sign the bundle we actually launch.
if command -v codesign >/dev/null 2>&1; then
    xattr -cr "$APP" 2>/dev/null || true
    codesign --force --deep --sign - "$APP" >/dev/null
fi

open "$APP"
