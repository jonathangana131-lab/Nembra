#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/Xcode27Simulator}"
DERIVED_DATA="${DERIVED_DATA:-${RUNNER_TEMP:-/tmp}/NembraDerivedData}"
RESULT_BUNDLE="$ARTIFACTS_DIR/NembraTests.xcresult"
ATTACHMENTS_DIR="$ARTIFACTS_DIR/test-attachments"
BUNDLE_ID="com.jonathangana131.nembra"
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$ATTACHMENTS_DIR"
rm -rf "$RESULT_BUNDLE"

XCODE_VERSION_OUTPUT="$(xcodebuild -version)"
XCODE_VERSION_LINE="${XCODE_VERSION_OUTPUT%%$'\n'*}"
if [[ ! "$XCODE_VERSION_LINE" =~ ^Xcode[[:space:]]+27([.]|[[:space:]]|$) ]]; then
  echo "The product evidence lane requires Xcode 27; found: $XCODE_VERSION_LINE" >&2
  exit 2
fi

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "source_sha=$(git rev-parse HEAD)"
  echo "expected_source_sha=${EXPECTED_SOURCE_SHA:-not-provided}"
  echo "runner_arch=$(uname -m)"
  sw_vers
  printf '%s\n' "$XCODE_VERSION_OUTPUT"
  xcrun simctl list runtimes
  xcrun simctl list devicetypes
} > "$ARTIFACTS_DIR/environment.txt"

SOURCE_SHA="$(git rev-parse HEAD)"
if [[ ! "${EXPECTED_SOURCE_SHA:-}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "EXPECTED_SOURCE_SHA must be one canonical lowercase 40-hex commit." >&2
  exit 8
fi
if [[ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]]; then
  echo "Checked-out source $SOURCE_SHA does not match requested exact head $EXPECTED_SOURCE_SHA." >&2
  exit 8
fi
WORKTREE_STATUS="$(git status --porcelain=v1 --untracked-files=all)"
if [[ -n "$WORKTREE_STATUS" ]]; then
  echo "The exact-head product evidence checkout is not clean." >&2
  printf '%s\n' "$WORKTREE_STATUS" >&2
  exit 8
fi

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
for x in items:
    if x.get("name")=="iPhone 12":
        print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "The required iPhone 12 Simulator device type is not installed on this runner." >&2
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
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "runtime=$RUNTIME_ID" >> "$ARTIFACTS_DIR/environment.txt"
echo "device_type=$DEVICE_TYPE" >> "$ARTIFACTS_DIR/environment.txt"
echo "simulator_udid=$UDID" >> "$ARTIFACTS_DIR/environment.txt"

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

# Keep UI-test attachments and direct screenshots on the same deterministic
# status-bar fixture. This is Simulator presentation evidence only.
xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 82 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 >/dev/null 2>&1 || true

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
    find "$ATTACHMENTS_DIR" -type f -print | sort \
      > "$ARTIFACTS_DIR/test-attachments.txt" || true
  else
    {
      echo "Attachment export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help export attachments || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1
  fi

  if ! xcrun xcresulttool get test-results metrics \
    --path "$RESULT_BUNDLE" \
    --compact \
    > "$ARTIFACTS_DIR/performance-metrics.json" \
    2> "$ARTIFACTS_DIR/logs/xcresult-performance-metrics.log"; then
    {
      echo "Performance metric export failed; the complete xcresult is still preserved."
      xcrun xcresulttool help get test-results metrics || true
    } >> "$ARTIFACTS_DIR/logs/xcresult-performance-metrics.log" 2>&1
    rm -f "$ARTIFACTS_DIR/performance-metrics.json"
  fi
fi

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "xcodebuild test failed with status $TEST_STATUS; preserving diagnostics before failing the job." >&2
  exit "$TEST_STATUS"
fi

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Nembra.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected built app was not found at $APP_PATH" >&2
  find "$DERIVED_DATA/Build/Products" -name 'Nembra.app' -print >&2 || true
  exit 4
fi

xcrun simctl install "$UDID" "$APP_PATH"

capture_state() {
  local state="$1"
  local appearance="${2:-dark}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" appearance "$appearance" >/dev/null 2>&1 || true
  local launch_output pid screenshot_path
  launch_output="$(
    SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state" \
    SIMCTL_CHILD_NEMBRA_SIMULATION_STORAGE_NAMESPACE="direct-${state}-${appearance}-${SOURCE_SHA}" \
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
  # Nembra Dark is the product default and AppRootView intentionally owns that
  # preference. Simulator appearance cannot turn these into light-app evidence,
  # so name and capture the artifact truthfully instead of emitting misleading
  # `*-light.png` files.
  capture_state "$state" dark
done

printf '%s\n' "Captured screenshots:" > "$ARTIFACTS_DIR/screenshots.txt"
find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' -print | sort >> "$ARTIFACTS_DIR/screenshots.txt"
# Product performance acceptance is deliberately separate from Debug functional
# and screenshot QA. The shared Nembra Performance scheme includes only the UI
# test target, uses Release, disables coverage, and launches without LLDB. This
# remains Simulator regression evidence only.
PERFORMANCE_RESULT_BUNDLE="$ARTIFACTS_DIR/NembraPerformanceTests.xcresult"
PERFORMANCE_DERIVED_DATA="${PERFORMANCE_DERIVED_DATA:-${RUNNER_TEMP:-/tmp}/NembraPerformanceDerivedData-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}"
PERFORMANCE_METRICS="$ARTIFACTS_DIR/performance-metrics.json"
PERFORMANCE_DETAILS="$ARTIFACTS_DIR/dashboard-performance-test-details.json"
PERFORMANCE_VALIDATOR="scripts/ci/validate_xcode27_dashboard_performance.py"
PERFORMANCE_TEST='NembraUITests/NembraUITests/testHorizonV4DriveSustainedRenderIslandHitchEvidence'

rm -rf "$PERFORMANCE_RESULT_BUNDLE"
rm -f \
  "$PERFORMANCE_METRICS" \
  "$PERFORMANCE_DETAILS" \
  "$ARTIFACTS_DIR/dashboard-performance-evidence.txt"
printf '%s\n' \
  'performance_configuration=Release' \
  'performance_debugger=disabled' \
  'performance_code_coverage=disabled' \
  'performance_sanitizers=disabled' \
  'performance_scope=Simulator-only regression evidence; not physical-device or display-refresh-rate proof' \
  >> "$ARTIFACTS_DIR/environment.txt"

set +e
set -o pipefail
xcodebuild \
  -project Nembra.xcodeproj \
  -scheme 'Nembra Performance' \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath "$PERFORMANCE_DERIVED_DATA" \
  -resultBundlePath "$PERFORMANCE_RESULT_BUNDLE" \
  -only-testing:"$PERFORMANCE_TEST" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -collect-test-diagnostics never \
  -enablePerformanceTestsDiagnostics NO \
  -enableCodeCoverage NO \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  test \
  | tee "$ARTIFACTS_DIR/logs/xcodebuild-performance-release.log"
PERFORMANCE_TEST_STATUS=${PIPESTATUS[0]}
set -e

if [[ ! -d "$PERFORMANCE_RESULT_BUNDLE" ]]; then
  echo "The Release performance result bundle is absent." \
    > "$ARTIFACTS_DIR/logs/dashboard-performance-validation.log"
  exit 9
fi

if ! xcrun xcresulttool get test-results metrics \
  --path "$PERFORMANCE_RESULT_BUNDLE" \
  --compact \
  > "$PERFORMANCE_METRICS" \
  2> "$ARTIFACTS_DIR/logs/xcresult-performance-metrics.log"; then
  echo "Performance metric export failed; the complete xcresult is still preserved." \
    >> "$ARTIFACTS_DIR/logs/xcresult-performance-metrics.log"
  rm -f "$PERFORMANCE_METRICS"
  exit 9
fi

if ! xcrun xcresulttool get test-results test-details \
  --path "$PERFORMANCE_RESULT_BUNDLE" \
  --test-id 'NembraUITests/testHorizonV4DriveSustainedRenderIslandHitchEvidence()' \
  --compact \
  > "$PERFORMANCE_DETAILS" \
  2> "$ARTIFACTS_DIR/logs/xcresult-dashboard-performance-details.log"; then
  echo "Sustained Dashboard performance test-details export failed." \
    >> "$ARTIFACTS_DIR/logs/xcresult-dashboard-performance-details.log"
  rm -f "$PERFORMANCE_DETAILS"
  exit 9
fi

if [[ "$PERFORMANCE_TEST_STATUS" -ne 0 ]]; then
  echo "Release Dashboard performance test failed with status $PERFORMANCE_TEST_STATUS." >&2
  exit "$PERFORMANCE_TEST_STATUS"
fi

if ! python3 "$PERFORMANCE_VALIDATOR" --self-test \
  > "$ARTIFACTS_DIR/logs/dashboard-performance-validator-fixtures.log" 2>&1; then
  echo "Dashboard performance validator self-tests failed." >&2
  exit 9
fi

if ! python3 "$PERFORMANCE_VALIDATOR" \
  --metrics "$PERFORMANCE_METRICS" \
  --details "$PERFORMANCE_DETAILS" \
  > "$ARTIFACTS_DIR/dashboard-performance-evidence.txt" \
  2> "$ARTIFACTS_DIR/logs/dashboard-performance-validation.log"; then
  echo "Required sustained Dashboard performance metrics are absent or invalid." >&2
  cat "$ARTIFACTS_DIR/logs/dashboard-performance-validation.log" >&2
  exit 9
fi
