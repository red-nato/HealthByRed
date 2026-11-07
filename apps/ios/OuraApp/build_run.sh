#!/bin/bash
# Build the real OuraApp: shared Rust core via the UniFFI OuraCore.xcframework,
# SwiftUI UI. Personal seed data requires HEALTH_INCLUDE_PERSONAL_DATA=1. Runs on the sim.
set -euo pipefail
cd "$(dirname "$0")/../../.."
REPO="$PWD"
APPDIR="$REPO/apps/ios/OuraApp"
GEN="$REPO/apps/ios/generated"
XCF="$REPO/apps/ios/OuraCore.xcframework/ios-arm64-simulator"
BUILD="$APPDIR/build"
APP="$BUILD/OuraApp.app"
TRIPLE="arm64-apple-ios17.0-simulator"
DEV="${1:-Codex-iPhone-17}"
BUNDLE_ID="md.thomas.openoura"

echo "==> refresh xcframework staticlib (release, iOS sim)"
cargo build -p oura-core --release --target aarch64-apple-ios-sim >/dev/null
cp "$REPO/target/aarch64-apple-ios-sim/release/liboura_core.a" "$XCF/liboura_core.a"

echo "==> compile SwiftUI app + UniFFI bindings, link core"
rm -rf "$BUILD"; mkdir -p "$APP"
xcrun -sdk iphonesimulator clang -std=c11 -O1 -target "$TRIPLE" \
    -c "$APPDIR/CrashCatch.c" -o "$BUILD/CrashCatch.o"
xcrun -sdk iphonesimulator swiftc \
    -target "$TRIPLE" -parse-as-library \
    -I "$GEN/headers" \
    "$GEN/oura_core.swift" "$APPDIR/Theme.swift" "$APPDIR/HealthHome.swift" "$APPDIR/HealthNavigation.swift" "$APPDIR/Modules.swift" "$APPDIR/DatabaseRestore.swift" "$APPDIR/OuraApp.swift" \
    "$APPDIR/Models.swift" "$APPDIR/Core.swift" "$APPDIR/Components.swift" "$APPDIR/Reports.swift" "$APPDIR/RawData.swift" "$APPDIR/HeartRate.swift" \
    "$APPDIR/BLETransport.swift" "$APPDIR/RingSync.swift" "$APPDIR/ProfileSettings.swift" \
    "$APPDIR/ModelProgress.swift" "$APPDIR/Diagnostics.swift" "$APPDIR/HealthExport.swift" "$APPDIR/DayExport.swift" "$APPDIR/WorkCoordinator.swift" "$BUILD/CrashCatch.o" \
    -L "$XCF" -loura_core -lsqlite3 \
    -o "$APP/OuraApp"
# Xcode expands $(PRODUCT_BUNDLE_IDENTIFIER) at build time; the raw-swiftc path doesn't,
# so substitute it here or LaunchServices registers the app under the literal variable
# and `simctl launch $BUNDLE_ID` fails with "returned nil" (FBSOpenApplication code 4).
cp "$APPDIR/Info.plist" "$APP/Info.plist"
cp "$APPDIR/Assets.xcassets/RingProduct.imageset/ring-product.png" "$APP/ring-product.png"
cp "$APPDIR/Assets.xcassets/RingRed.imageset/ring-red.png" "$APP/ring-red.png"
cp "$APPDIR/Assets.xcassets/RingOff.imageset/ring-off.png" "$APP/ring-off.png"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"

echo "==> optional development seed data"
# Development-only opt-in: never put a personal database in an app by default.
if [[ "${HEALTH_INCLUDE_PERSONAL_DATA:-0}" == "1" ]]; then
    sqlite3 "$REPO/oura.db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    cp "$REPO/oura.db" "$APP/oura.db"
fi

echo "==> boot + install + launch + screenshot"
xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1 || true
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" "$BUNDLE_ID"
sleep 2
xcrun simctl io "$DEV" screenshot "$BUILD/screenshot.png"
echo "screenshot: $BUILD/screenshot.png"
