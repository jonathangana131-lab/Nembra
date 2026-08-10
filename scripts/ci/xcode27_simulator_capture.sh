#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/Xcode27Simulator}"
DERIVED_DATA="${DERIVED_DATA:-${RUNNER_TEMP:-/tmp}/NembraDerivedData}"
RESULT_BUNDLE="$ARTIFACTS_DIR/NembraTests.xcresult"
ATTACHMENTS_DIR="$ARTIFACTS_DIR/test-attachments"
REDUCE_MOTION_RESULT_BUNDLE="$ARTIFACTS_DIR/NembraReduceMotionTests.xcresult"
REDUCE_MOTION_ATTACHMENTS_DIR="$ARTIFACTS_DIR/reduce-motion-test-attachments"
BUNDLE_ID="com.jonathangana131.nembra"
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$ATTACHMENTS_DIR"
rm -rf "$RESULT_BUNDLE" "$REDUCE_MOTION_RESULT_BUNDLE" "$REDUCE_MOTION_ATTACHMENTS_DIR"

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner_arch=$(uname -m)"
  sw_vers
  xcodebuild -version
  xcrun simctl list runtimes
  xcrun simctl list devicetypes
} > "$ARTIFACTS_DIR/environment.txt"

RUNTIME_ID="$({ xcrun simctl list runtimes -j | python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || {
  echo "No iOS 27 Simulator runtime is available on this runner." >&2
  exit 2
}

DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | python3 -c '
import json,sys
items=json.load(sys.stdin)["devicetypes"]
preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]
for name in preferred:
    for x in items:
        if x.get("name")==name:
            print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "No supported iPhone Simulator device type found." >&2
  exit 3
}

SIM_NAME="Nembra Xcode27 CI ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process == "Nembra"' \
    > "$ARTIFACTS_DIR/logs/nembra-system.log" 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "runtime=$RUNTIME_ID" >> "$ARTIFACTS_DIR/environment.txt"
echo "device_type=$DEVICE_TYPE" >> "$ARTIFACTS_DIR/environment.txt"
echo "simulator_udid=$UDID" >> "$ARTIFACTS_DIR/environment.txt"

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  test \
  | tee "$ARTIFACTS_DIR/logs/xcodebuild-test.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$ATTACHMENTS_DIR" \
    > "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1; then
    find "$ATTACHMENTS_DIR" -type f -maxdepth 2 -print | sort \
      > "$ARTIFACTS_DIR/test-attachments.txt" || true
  else
    {
      echo "Attachment export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help export attachments || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1
  fi
fi

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "xcodebuild test failed with status $TEST_STATUS; preserving diagnostics before failing the job." >&2
  exit "$TEST_STATUS"
fi

# Accessibility runtime acceptance uses the real Simulator setting rather than an
# app launch override. Continuous 60 Hz motion must be suppressed while semantic
# LIVE/RETAINED/UNAVAILABLE truth and the mounted landscape Energy Rail remain
# correct. Re-run only the two product states needed for this visual/accessibility
# proof and export their keep-always screenshots separately.
echo "reduce_motion_runtime_qa=enabled" >> "$ARTIFACTS_DIR/environment.txt"
xcrun simctl ui "$UDID" reduce_motion enabled

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$REDUCE_MOTION_RESULT_BUNDLE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -collect-test-diagnostics never \
  -only-testing:NembraUITests/NembraUITests/testLandscapeDashboardIsDedicatedCockpitAndHidesMovingControls \
  -only-testing:NembraUITests/NembraUITests/testLandscapeDashboardRetainedPowerAfterReconnectIsExplicitLastKnown \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  test \
  | tee "$ARTIFACTS_DIR/logs/xcodebuild-reduce-motion-test.log"
REDUCE_MOTION_TEST_STATUS=${PIPESTATUS[0]}
set -e

xcrun simctl ui "$UDID" reduce_motion disabled || true

if [[ -d "$REDUCE_MOTION_RESULT_BUNDLE" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$REDUCE_MOTION_RESULT_BUNDLE" \
    --output-path "$REDUCE_MOTION_ATTACHMENTS_DIR" \
    > "$ARTIFACTS_DIR/logs/xcresult-reduce-motion-attachments.log" 2>&1; then
    find "$REDUCE_MOTION_ATTACHMENTS_DIR" -type f -maxdepth 2 -print | sort \
      > "$ARTIFACTS_DIR/reduce-motion-test-attachments.txt" || true
  else
    {
      echo "Reduce Motion attachment export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help export attachments || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-reduce-motion-attachments.log" 2>&1
  fi
fi

if [[ "$REDUCE_MOTION_TEST_STATUS" -ne 0 ]]; then
  echo "Reduce Motion exact-head UI acceptance failed with status $REDUCE_MOTION_TEST_STATUS." >&2
  exit "$REDUCE_MOTION_TEST_STATUS"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Nembra.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected built app was not found at $APP_PATH" >&2
  find "$DERIVED_DATA/Build/Products" -name 'Nembra.app' -print >&2 || true
  exit 4
fi

xcrun simctl install "$UDID" "$APP_PATH"

xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 82 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 >/dev/null 2>&1 || true

capture_state() {
  local state="$1"
  local appearance="${2:-light}"
  local suffix="${3:-}"
  local artifact_name="${state}-${appearance}"
  if [[ -n "$suffix" ]]; then
    artifact_name="${artifact_name}-${suffix}"
  fi

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance" >/dev/null 2>&1 || true
  local launch_output pid screenshot_path
  launch_output="$(
    SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state" \
      xcrun simctl launch "$UDID" "$BUNDLE_ID" \
      | tee "$ARTIFACTS_DIR/logs/launch-${artifact_name}.log"
  )"
  pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse launched Nembra process ID from: $launch_output" >&2
    exit 5
  fi

  sleep 2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Nembra exited before ${artifact_name} screenshot capture." >&2
    exit 6
  fi

  screenshot_path="$ARTIFACTS_DIR/screenshots/${artifact_name}.png"
  xcrun simctl io "$UDID" screenshot "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "Simulator screenshot was not created for ${artifact_name}." >&2
    exit 7
  fi
}

set_content_size() {
  local size="$1"
  if ! xcrun simctl ui "$UDID" content_size "$size" \
      > "$ARTIFACTS_DIR/logs/content-size-${size}.log" 2>&1; then
    {
      echo "Could not set Simulator content size to ${size}."
      echo "Exact simctl UI help follows so the failure remains diagnosable on the Xcode 27 runner:"
      xcrun simctl help ui || true
    } >> "$ARTIFACTS_DIR/logs/content-size-${size}.log" 2>&1
    return 1
  fi
}

# Baseline product matrix at the normal system text size.
set_content_size large || exit 8
for state in \
  cold-disconnected \
  reconnecting \
  connected-stopped \
  riding \
  low-battery \
  bluetooth-off \
  permission-denied \
  scooter-unavailable \
  unsupported-configuration
do
  capture_state "$state" light
done
capture_state connected-stopped dark
capture_state reconnecting dark

# Accessibility Dynamic Type uses the real iOS Simulator system preference rather
# than a SwiftUI environment override. AX5 is the maximum accessibility category.
AX5_CONTENT_SIZE="accessibility-extra-extra-extra-large"
set_content_size "$AX5_CONTENT_SIZE" || exit 9
echo "dashboard_ax5_content_size=$AX5_CONTENT_SIZE" >> "$ARTIFACTS_DIR/environment.txt"
capture_state connected-stopped light ax5
capture_state riding light ax5

# Leave diagnostics/subsequent invocations in the normal baseline environment.
set_content_size large || exit 10

printf '%s\n' "Captured screenshots:" > "$ARTIFACTS_DIR/screenshots.txt"
find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' -print | sort >> "$ARTIFACTS_DIR/screenshots.txt"
