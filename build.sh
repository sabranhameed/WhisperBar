#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — build WhisperBar and package it as a .app bundle
# Usage:  chmod +x build.sh && ./build.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_NAME="WhisperBar"
BUNDLE_ID="com.whisperbar.app"
VERSION="1.0.0"
MIN_OS="13.0"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/release"

echo "▶  Building ${APP_NAME} (release)…"
swift build -c release 2>&1

echo "▶  Packaging ${APP_BUNDLE}…"

# ── Create bundle skeleton ────────────────────────────────────────────────────
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# ── Copy binary ───────────────────────────────────────────────────────────────
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# ── Write Info.plist ──────────────────────────────────────────────────────────
cat > "${APP_BUNDLE}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>       <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>             <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>      <string>WhisperBar</string>
    <key>CFBundleVersion</key>          <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>NSPrincipalClass</key>         <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>   <string>${MIN_OS}</string>
    <key>NSHighResolutionCapable</key>  <true/>

    <!-- Hide from Dock — menu bar only -->
    <key>LSUIElement</key> <true/>

    <!-- Privacy usage descriptions -->
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperBar records your voice to transcribe it locally using Whisper AI.</string>

    <!-- Required for CGEvent-based paste -->
    <key>NSAppleEventsUsageDescription</key>
    <string>WhisperBar needs to send key events to paste transcribed text into other apps.</string>
</dict>
</plist>
PLIST

# ── Ad-hoc code sign (lets Gatekeeper run it without App Store) ───────────────
echo "▶  Ad-hoc signing…"
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "✅  Done!  ${APP_BUNDLE} is ready."
echo ""
echo "   To install:  cp -r ${APP_BUNDLE} /Applications/"
echo "   To run now:  open ${APP_BUNDLE}"
echo ""
echo "   First launch: Whisper will download the chosen model (~74 MB for 'base')."
echo "   After that the app runs fully offline."
echo ""
echo "   NOTE: On first open macOS may warn 'unidentified developer'."
echo "   Right-click → Open to bypass, or run:"
echo "   xattr -d com.apple.quarantine ${APP_BUNDLE}"
