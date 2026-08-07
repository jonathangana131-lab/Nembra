#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT/Artifacts/Xcode27Simulator}"
DERIVED_DATA="${DERIVED_DATA:-${RUNNER_TEMP:-/tmp}/NembraDerivedData}"
RESULT_BUNDLE="$ARTIFACTS_DIR/NembraTests.xcresult"
ATTACHMENTS_DIR="$ARTIFACTS_DIR/test-attachments"
BUNDLE_ID="com.jonathangana131.nembra"
ACCESSIBILITY_CAPTURE="${NEMBRA_ACCESSIBILITY_CAPTURE:-0}"
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$ATTACHMENTS_DIR"
rm -rf "$RESULT_BUNDLE"

case "$ACCESSIBILITY_CAPTURE" in
  0|1) ;;
  *)
    echo "NEMBRA_ACCESSIBILITY_CAPTURE must be 0 or 1, got: $ACCESSIBILITY_CAPTURE" >&2
    exit 1
    ;;
esac

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner_arch=$(uname -m)"
  echo "accessibility_capture=$ACCESSIBILITY_CAPTURE"
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

SIMCTL_UI_HELP="$ARTIFACTS_DIR/logs/simctl-ui-help.txt"
set +e
xcrun simctl help ui > "$SIMCTL_UI_HELP" 2>&1
SIMCTL_UI_HELP_STATUS=$?
set -e
echo "simctl_ui_help_status=$SIMCTL_UI_HELP_STATUS" >> "$ARTIFACTS_DIR/environment.txt"

simctl_ui_supports() {
  local setting="$1"
  [[ "$SIMCTL_UI_HELP_STATUS" -eq 0 ]] && \
    grep -Eq "(^|[[:space:]])${setting}([[:space:]]|$)" "$SIMCTL_UI_HELP"
}

read_simctl_ui_setting() {
  local setting="$1"
  xcrun simctl ui "$UDID" "$setting" 2>/dev/null | tr -d '\r' | tail -n 1
}

set_simctl_ui_setting_verified() {
  local setting="$1"
  local requested="$2"
  local log_path="$3"
  local observed

  if ! simctl_ui_supports "$setting"; then
    printf 'setting=%s\nrequested=%s\nresult=unadvertised\n' "$setting" "$requested" > "$log_path"
    return 1
  fi

  if ! xcrun simctl ui "$UDID" "$setting" "$requested" > "$log_path" 2>&1; then
    printf 'setting=%s\nrequested=%s\nresult=setter-failed\n' "$setting" "$requested" >> "$log_path"
    return 1
  fi

  observed="$(read_simctl_ui_setting "$setting" || true)"
  printf 'setting=%s\nrequested=%s\nobserved=%s\n' "$setting" "$requested" "${observed:-<empty>}" >> "$log_path"
  [[ "$observed" == "$requested" ]]
}

record_simctl_ui_state() {
  local output_path="$1"
  {
    echo "simctl_ui_help_status=$SIMCTL_UI_HELP_STATUS"
    if simctl_ui_supports appearance; then
      echo "appearance=$(read_simctl_ui_setting appearance || echo query-error)"
    else
      echo "appearance=unadvertised"
    fi
    if simctl_ui_supports increase_contrast; then
      echo "increase_contrast=$(read_simctl_ui_setting increase_contrast || echo query-error)"
    else
      echo "increase_contrast=unadvertised"
    fi
    if simctl_ui_supports content_size; then
      echo "content_size=$(read_simctl_ui_setting content_size || echo query-error)"
    else
      echo "content_size=unadvertised"
    fi
  } > "$output_path"
}

record_simctl_ui_state "$ARTIFACTS_DIR/logs/simctl-ui-state-before.txt"

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
  local variant="${3:-}"
  local artifact_key="${state}-${appearance}"
  if [[ -n "$variant" ]]; then
    artifact_key="${artifact_key}-${variant}"
  fi

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  if [[ -n "$variant" ]]; then
    if ! set_simctl_ui_setting_verified appearance "$appearance" \
      "$ARTIFACTS_DIR/logs/simctl-appearance-${artifact_key}.log"; then
      echo "Could not verify ${appearance} appearance for accessibility capture ${artifact_key}." >&2
      exit 8
    fi
  else
    xcrun simctl ui "$UDID" appearance "$appearance" >/dev/null 2>&1 || true
  fi

  local launch_output pid screenshot_path
  launch_output="$(
    SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state" \
      xcrun simctl launch "$UDID" "$BUNDLE_ID" \
      | tee "$ARTIFACTS_DIR/logs/launch-${artifact_key}.log"
  )"
  pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse launched Nembra process ID from: $launch_output" >&2
    exit 5
  fi

  sleep 2
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Nembra exited before ${artifact_key} screenshot capture." >&2
    exit 6
  fi

  screenshot_path="$ARTIFACTS_DIR/screenshots/${artifact_key}.png"
  xcrun simctl io "$UDID" screenshot "$screenshot_path"
  if [[ ! -s "$screenshot_path" ]]; then
    echo "Simulator screenshot was not created for ${artifact_key}." >&2
    exit 7
  fi
}

capture_increase_contrast_matrix() {
  if ! simctl_ui_supports increase_contrast; then
    echo "Accessibility capture requested, but this Xcode runner does not advertise simctl ui increase_contrast." >&2
    exit 8
  fi

  local original_contrast applied_contrast restored_contrast
  original_contrast="$(read_simctl_ui_setting increase_contrast || true)"
  case "$original_contrast" in
    enabled|disabled) ;;
    *)
      echo "Could not establish initial Increase Contrast state; got: ${original_contrast:-<empty>}" >&2
      exit 8
      ;;
  esac

  if ! xcrun simctl ui "$UDID" increase_contrast enabled \
    > "$ARTIFACTS_DIR/logs/simctl-increase-contrast-set.log" 2>&1; then
    echo "Runner advertises Increase Contrast but could not enable it; see simctl-increase-contrast-set.log." >&2
    exit 8
  fi
  applied_contrast="$(read_simctl_ui_setting increase_contrast || true)"
  if [[ "$applied_contrast" != "enabled" ]]; then
    echo "Increase Contrast readback mismatch after enable: ${applied_contrast:-<empty>}" >&2
    exit 8
  fi

  {
    echo "requested=enabled"
    echo "initial=$original_contrast"
    echo "applied=$applied_contrast"
  } > "$ARTIFACTS_DIR/logs/increase-contrast-state.txt"

  capture_state connected-stopped light increase-contrast
  capture_state reconnecting light increase-contrast
  capture_state low-battery light increase-contrast
  capture_state connected-stopped dark increase-contrast

  if ! xcrun simctl ui "$UDID" increase_contrast "$original_contrast" \
    >> "$ARTIFACTS_DIR/logs/simctl-increase-contrast-set.log" 2>&1; then
    echo "Could not restore Increase Contrast to $original_contrast." >&2
    exit 8
  fi
  restored_contrast="$(read_simctl_ui_setting increase_contrast || true)"
  if [[ "$restored_contrast" != "$original_contrast" ]]; then
    echo "Increase Contrast readback mismatch after restore: ${restored_contrast:-<empty>}" >&2
    exit 8
  fi
  echo "restored=$restored_contrast" >> "$ARTIFACTS_DIR/logs/increase-contrast-state.txt"
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

if [[ "$ACCESSIBILITY_CAPTURE" == "1" ]]; then
  capture_increase_contrast_matrix
fi
record_simctl_ui_state "$ARTIFACTS_DIR/logs/simctl-ui-state-after.txt"

printf '%s\n' "Captured screenshots:" > "$ARTIFACTS_DIR/screenshots.txt"
find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' -print | sort >> "$ARTIFACTS_DIR/screenshots.txt"
