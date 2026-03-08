#!/bin/bash
set -e

export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH:$HOME/.maestro/bin"

DEVICE="iPhone 16 Pro Max"
APP_BUNDLE="com.andresboedo.add2wallet"
BUILD_DIR="$HOME/repos/add2wallet/ios/build/Debug-iphonesimulator"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "📱 Booting $DEVICE..."
xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator

echo "⏳ Waiting for simulator..."
sleep 5

echo "📦 Installing app..."
xcrun simctl install booted "$BUILD_DIR/Add2Wallet.app"

echo "📸 Taking screenshots..."
for flow in "$SCRIPT_DIR"/0*.yaml; do
  echo "  → $(basename "$flow")"
  maestro test "$flow"
done

echo "✅ Done! Screenshots in $SCRIPT_DIR/screenshots/"
ls "$SCRIPT_DIR"/*.png 2>/dev/null || true
