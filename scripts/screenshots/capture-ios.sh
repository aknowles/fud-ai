#!/bin/bash
# README and website screenshots from the Debug app on a headless iOS simulator, with the
# demo data and screens in ios/calorietracker/Services/ScreenshotMode.swift.
#
#   scripts/screenshots/capture-ios.sh [output-dir]
#
# Uses (and creates once) a dedicated "Fud AI Screenshots" iPhone 17 Pro simulator, never
# opens Simulator.app, and shuts the simulator down when done. Output: one PNG per scene.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/scripts/screenshots/out}"
DEVICE_NAME="Fud AI Screenshots"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
BUNDLE="com.apoorvdarshan.calorietracker.debug"
DERIVED="${DERIVED:-$HOME/Library/Developer/Xcode/DerivedData/calorietracker-screenshots}"
# scene:file
SCENES=(
  home:home
  voice:live-voice
  food:food
  nutrition:nutrition
  progress:progress
  coach:coach
  workouts:workouts
  aiProviders:ai-providers
  voiceSettings:voice-settings
)

mkdir -p "$OUT"
UDID=$(xcrun simctl list devices available | grep -F "$DEVICE_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/' || true)
if [ -z "$UDID" ]; then
  RUNTIME=$(xcrun simctl list runtimes available | grep -E '^iOS' | tail -1 | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+).*/\1/')
  UDID=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_TYPE" "$RUNTIME")
fi
echo "Simulator $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcodebuild -project "$ROOT/ios/calorietracker.xcodeproj" -scheme calorietracker -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build -quiet
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/calorietracker.app"

DATA=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
mkdir -p "$DATA/Documents/ScreenshotDemo"
cp "$ROOT/scripts/screenshots/demo-photos/"*.jpg "$DATA/Documents/ScreenshotDemo/"

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" --ui-testing --ui-testing-reset --ui-testing-onboarded --screenshot-demo \
    -screenshotScene "$1" -AppleLanguages "(en)" -AppleLocale en_US \
    -didPromptReviewAfterFirstLog YES -WorkoutVectorsBaseURL none >/dev/null
}

# The first launch after an install is slow; warm up so the first capture isn't blank.
launch home
sleep 12

for pair in "${SCENES[@]}"; do
  scene="${pair%%:*}"; file="${pair##*:}"
  for attempt in 1 2 3; do
    launch "$scene"
    sleep "${SCREENSHOT_WAIT:-8}"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$file.png" >/dev/null 2>&1
    # A frame caught mid-launch is nearly all black and compresses to almost nothing.
    [ "$(stat -f %z "$OUT/$file.png")" -gt 150000 ] && break
    echo "retrying $file (blank frame)"
  done
  echo "captured $file"
done

xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear
xcrun simctl shutdown "$UDID"
