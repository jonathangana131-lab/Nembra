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
AX5_RESULT_BUNDLE="$ARTIFACTS_DIR/NembraAX5Tests.xcresult"
AX5_ATTACHMENTS_DIR="$ARTIFACTS_DIR/ax5-test-attachments"
BUNDLE_ID="com.jonathangana131.nembra"
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$ATTACHMENTS_DIR"
rm -rf \
  "$RESULT_BUNDLE" \
  "$REDUCE_MOTION_RESULT_BUNDLE" \
  "$REDUCE_MOTION_ATTACHMENTS_DIR" \
  "$AX5_RESULT_BUNDLE" \
  "$AX5_ATTACHMENTS_DIR"

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

# CoreSimulator's `simctl ui` action spelling has changed across Xcode/runtime
# generations. Probe the known spellings instead of letting `set -e` terminate
# the acceptance job before the Reduce Motion rerun, and preserve authoritative
# runner help if none is supported.
set_reduce_motion() {
  local requested_state="$1"
  local action status
  local log_path="$ARTIFACTS_DIR/logs/simctl-reduce-motion.log"
  : > "$log_path"

  for action in reduce_motion reduceMotion reduce-motion; do
    echo "probe_action=$action state=$requested_state" >> "$log_path"
    set +e
    xcrun simctl ui "$UDID" "$action" "$requested_state" >> "$log_path" 2>&1
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
      echo "reduce_motion_simctl_action=$action" >> "$ARTIFACTS_DIR/environment.txt"
      echo "accepted_action=$action state=$requested_state" >> "$log_path"
      return 0
    fi
    echo "rejected_action=$action status=$status" >> "$log_path"
  done

  {
    echo "No probed Reduce Motion simctl action was accepted. Runner help follows."
    xcrun simctl help ui || true
    xcrun simctl ui "$UDID" help || true
  } >> "$log_path" 2>&1
  return 1
}

# The primary exact-head test pass above already exercises package/app Reduce Motion
# semantics. When this CoreSimulator build also exposes a real system-level Reduce
# Motion `simctl ui` action, add the stronger end-to-end accessibility rerun and
# keep-always screenshots. Xcode 27A5228h / iOS 27.0 currently exposes only
# appearance, increase_contrast, and content_size; treating that missing CLI
# capability as a product failure would make a green product permanently red for a
# runner limitation. Record the capability gap explicitly and never claim the
# system-setting rerun happened when it did not.
echo "reduce_motion_semantic_qa=covered_by_primary_exact_head_tests" >> "$ARTIFACTS_DIR/environment.txt"
REDUCE_MOTION_RUNTIME_AVAILABLE=0
if set_reduce_motion enabled; then
  REDUCE_MOTION_RUNTIME_AVAILABLE=1
  echo "reduce_motion_runtime_qa=enabled" >> "$ARTIFACTS_DIR/environment.txt"
else
  echo "reduce_motion_runtime_qa=unsupported_by_simctl" >> "$ARTIFACTS_DIR/environment.txt"
  echo "Reduce Motion system-setting rerun unavailable on this Xcode/iOS Simulator pair; preserving runner help and relying only on the already-green semantic/unit coverage." >&2
fi

if [[ "$REDUCE_MOTION_RUNTIME_AVAILABLE" -eq 1 ]]; then
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

  set_reduce_motion disabled || true

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
fi

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

# Real system Accessibility Dynamic Type acceptance. AppRootView selects the
# landscape cockpit from vertical size class, so the existing landscape XCUITests
# remain the authority for orientation and product state. AX5 changes only the
# Simulator system text size; no SwiftUI/app launch override is introduced.
AX5_CONTENT_SIZE="accessibility-extra-extra-extra-large"
set_content_size "$AX5_CONTENT_SIZE" || exit 8
echo "dashboard_ax5_content_size=$AX5_CONTENT_SIZE" >> "$ARTIFACTS_DIR/environment.txt"

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme Nembra \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  -resultBundlePath "$AX5_RESULT_BUNDLE" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -collect-test-diagnostics never \
  -only-testing:NembraUITests/NembraUITests/testLandscapeDashboardIsDedicatedCockpitAndHidesMovingControls \
  -only-testing:NembraUITests/NembraUITests/testLandscapeDashboardRetainedPowerAfterReconnectIsExplicitLastKnown \
  -only-testing:NembraUITests/NembraUITests/testLandscapeDashboardStoppedControlsConfirmEveryModePersonality \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  test \
  | tee "$ARTIFACTS_DIR/logs/xcodebuild-ax5-test.log"
AX5_TEST_STATUS=${PIPESTATUS[0]}
set -e

# Restore the ordinary baseline before any later manual capture/diagnostics. If
# restoration fails, preserve the AX5 result bundle but do not create misleading
# normal-size screenshot filenames under an unknown system text-size state.
AX5_RESTORE_STATUS=0
if ! set_content_size large; then
  AX5_RESTORE_STATUS=1
fi

if [[ -d "$AX5_RESULT_BUNDLE" ]]; then
  if xcrun xcresulttool export attachments \
    --path "$AX5_RESULT_BUNDLE" \
    --output-path "$AX5_ATTACHMENTS_DIR" \
    > "$ARTIFACTS_DIR/logs/xcresult-ax5-attachments.log" 2>&1; then
    find "$AX5_ATTACHMENTS_DIR" -type f -maxdepth 2 -print | sort \
      > "$ARTIFACTS_DIR/ax5-test-attachments.txt" || true
  else
    {
      echo "AX5 attachment export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help export attachments || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-ax5-attachments.log" 2>&1
  fi
fi

if [[ "$AX5_TEST_STATUS" -ne 0 ]]; then
  echo "AX5 landscape Dashboard acceptance failed with status $AX5_TEST_STATUS." >&2
  exit "$AX5_TEST_STATUS"
fi
if [[ "$AX5_RESTORE_STATUS" -ne 0 ]]; then
  echo "AX5 evidence passed, but restoring Simulator content size to Large failed; refusing mislabeled baseline captures." >&2
  exit 9
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
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance" >/dev/null 2>&1 || true
  local launch_output pid screenshot_path
  launch_output="$(
    SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state" \
      xcrun simctl launch "$UDID" "$BUNDLE_ID" \
      | tee "$ARTIFACTS_DIR/logs/launch-${state}-${appearance}.log"
  )"
  pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse launched Nembra process ID from: $launch_output" >&2
    exit 5
  fi

  sleep 2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Nembra exited before ${state}/${appearance} screenshot capture." >&2
    exit 6
  fi

  screenshot_path="$ARTIFACTS_DIR/screenshots/${state}-${appearance}.png"
  xcrun simctl io "$UDID" screenshot "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "Simulator screenshot was not created for ${state}/${appearance}." >&2
    exit 7
  fi
}

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

printf '%s\n' "Captured screenshots:" > "$ARTIFACTS_DIR/screenshots.txt"
find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' -print | sort >> "$ARTIFACTS_DIR/screenshots.txt"
