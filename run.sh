#!/bin/bash
# Isolyn — build + wrap in minimal .app bundle + launch
# Usage: ./run.sh [--release]
#
# Why this exists: SwiftPM executables don't produce .app bundles, and macOS
# SwiftUI requires Bundle.main.bundleIdentifier to create windows. This
# script wraps the compiled binary in a minimal .app structure so the app
# launches correctly. For Xcode debugging, open Package.swift directly.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="debug"
[[ "${1:-}" == "--release" ]] && CONFIG="release"

echo "🔨 Building ($CONFIG)..."
swift build -c "$CONFIG" 2>&1 | tail -1

BINARY=".build/$([ "$CONFIG" = "debug" ] && echo "debug" || echo "release")/IsolynApp"
[ -f "$BINARY" ] || { echo "❌ binary not found at $BINARY"; exit 1; }

APP="build/Isolyn.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/Isolyn"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.isolyn.app</string>
<key>CFBundleName</key><string>Isolyn</string>
<key>CFBundleExecutable</key><string>Isolyn</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict></plist>
PLIST

echo "🚀 Launching Isolyn…"
open "$APP"
