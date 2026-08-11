#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${APP_PATH:-/tmp/NembraCaptureProvenanceDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${RUNNER_TEMP:-/tmp}/NembraCaptureStandaloneVisualEvidence}"
EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
EXPECTED_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1"
EXPECTED_DEVICE_NAME="iPhone 12"
EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"
PNG_CONTENT_GUARD="$ROOT_DIR/scripts/ci/capture_visual_png_content_guard.py"
MAX_SCREENSHOT_ATTEMPTS=40
SCREENSHOT_RETRY_SECONDS=0.25

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Standalone Capture visual evidence requires macOS/CoreSimulator." >&2
  exit 2
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Standalone Capture app was not found at: $APP_PATH" >&2
  exit 3
fi
if [[ ! -x /usr/bin/plutil ]]; then
  echo "plutil is required to verify the standalone Capture build." >&2
  exit 4
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun/CoreSimulator is required to capture standalone Capture visual evidence." >&2
  exit 5
fi
if [[ ! -f "$PNG_CONTENT_GUARD" ]]; then
  echo "Standalone Capture rendered-content guard is missing: $PNG_CONTENT_GUARD" >&2
  exit 24
fi

INFO_PLIST="$APP_PATH/Info.plist"
IDENTITY_SOURCE="NembraApp/App/NembraCaptureBuildIdentity.swift"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Standalone Capture Info.plist is missing." >&2
  exit 6
fi
if [[ ! -f "$IDENTITY_SOURCE" ]] || ! grep -Fq "static let requiredFieldProcedureIdentifier = \"$EXPECTED_PROCEDURE_IDENTIFIER\"" "$IDENTITY_SOURCE"; then
  echo "Standalone Capture source does not declare the required canonical stationary procedure." >&2
  exit 19
fi

BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$INFO_PLIST")"
SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$INFO_PLIST")"
TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$INFO_PLIST" 2>/dev/null || true)"
PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected standalone Capture bundle identifier: $BUNDLE_ID" >&2
  exit 7
fi
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Standalone Capture source identity must be one lowercase 40-hex SHA." >&2
  exit 8
fi
if [[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]; then
  echo "Public standalone visual evidence must not carry Tuya dependency authority: $TUYA_DEPENDENCY_LOCK_SHA256" >&2
  exit 9
fi
if [[ "$PROCEDURE_IDENTIFIER" != "$EXPECTED_PROCEDURE_IDENTIFIER" ]]; then
  echo "Standalone Capture built procedure does not rendezvous with the required stationary procedure: $PROCEDURE_IDENTIFIER" >&2
  exit 23
fi
EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"
if [[ "$BUILD_IDENTIFIER" != "$EXPECTED_BUILD_IDENTIFIER" ]]; then
  echo "Standalone Capture build identifier does not rendezvous with its embedded source SHA." >&2
  exit 10
fi

CHECKOUT_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
if [[ "$SOURCE_SHA" != "$CHECKOUT_SHA" ]]; then
  echo "Standalone visual evidence app was not stamped from the exact checked-out source: app=$SOURCE_SHA checkout=$CHECKOUT_SHA" >&2
  exit 20
fi

if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "Refusing to mix or overwrite prior standalone Capture visual evidence: $ARTIFACTS_DIR" >&2
  exit 11
fi
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs"

RUNTIME_ID="$({ xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || {
  echo "No iOS 27 Simulator runtime is available on this runner." >&2
  exit 12
}

DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys
items=json.load(sys.stdin)["devicetypes"]
for x in items:
    if x.get("name") == "iPhone 12":
        print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "The required iPhone 12 Simulator device type is unavailable; no newer-device fallback may satisfy the V14 baseline." >&2
  exit 13
}
if [[ "$DEVICE_TYPE" != "$EXPECTED_DEVICE_TYPE" ]]; then
  echo "Unexpected iPhone 12 Simulator device type: $DEVICE_TYPE" >&2
  exit 21
fi

SIM_NAME="Nembra Capture Visual ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 5m --style compact --predicate 'process contains[c] "Nembra"' > "$ARTIFACTS_DIR/logs/nembra-capture-system.log" 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

capture_ready_screenshot() {
  local output_path="$1"
  local label="$2"
  local pending_path="${output_path%.png}.pending.png"
  local attempt

  rm -f "$output_path" "$pending_path"
  for ((attempt = 1; attempt <= MAX_SCREENSHOT_ATTEMPTS; attempt++)); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      echo "$label: standalone Nembra Capture exited before rendered visual evidence was ready." >&2
      return 1
    fi

    if ! xcrun simctl io "$UDID" screenshot "$pending_path" >/dev/null; then
      echo "$label: simctl screenshot attempt $attempt/$MAX_SCREENSHOT_ATTEMPTS failed." >&2
    elif /usr/bin/python3 "$PNG_CONTENT_GUARD" "$pending_path" --label "$label attempt $attempt/$MAX_SCREENSHOT_ATTEMPTS" \
      2>&1 | tee -a "$ARTIFACTS_DIR/logs/screenshot-readiness.log"; then
      mv "$pending_path" "$output_path"
      echo "$label: rendered-content readiness accepted on attempt $attempt/$MAX_SCREENSHOT_ATTEMPTS." \
        | tee -a "$ARTIFACTS_DIR/logs/screenshot-readiness.log"
      return 0
    fi

    if (( attempt < MAX_SCREENSHOT_ATTEMPTS )); then
      sleep "$SCREENSHOT_RETRY_SECONDS"
    fi
  done

  echo "$label: no screenshot proved non-trivial rendered app content after $MAX_SCREENSHOT_ATTEMPTS bounded attempts; refusing visual acceptance." \
    | tee -a "$ARTIFACTS_DIR/logs/screenshot-readiness.log" >&2
  return 1
}

launch_standalone_capture() {
  local tee_mode="$1"
  local launch_output
  if [[ "$tee_mode" == "append" ]]; then
    launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" | tee -a "$ARTIFACTS_DIR/logs/launch.log")"
  else
    launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" | tee "$ARTIFACTS_DIR/logs/launch.log")"
  fi
  pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse standalone Capture process ID from: $launch_output" >&2
    return 1
  fi
}

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 82 --wifiBars 3 --cellularMode active --cellularBars 4 >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" appearance dark

while IFS= read -r variable_name; do
  case "$variable_name" in
    SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)
      echo "Refusing standalone visual evidence with inherited synthetic authority: $variable_name" >&2
      exit 18
      ;;
  esac
done < <(compgen -v)

if ! launch_standalone_capture truncate; then
  exit 14
fi

STANDARD_SCREENSHOT="$ARTIFACTS_DIR/screenshots/standalone-unprovisioned-dark-iphone12.png"
if ! capture_ready_screenshot "$STANDARD_SCREENSHOT" "Standard iPhone 12 Capture root"; then
  exit 16
fi

# Relaunch after changing Dynamic Type so AX XXXL evidence cannot accidentally
# admit a still-rendered standard-size frame while the environment transition is pending.
xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
if ! launch_standalone_capture append; then
  exit 22
fi
AX5_SCREENSHOT="$ARTIFACTS_DIR/screenshots/standalone-unprovisioned-dark-iphone12-ax5.png"
if ! capture_ready_screenshot "$AX5_SCREENSHOT" "Accessibility XXXL iPhone 12 Capture root"; then
  exit 22
fi
xcrun simctl ui "$UDID" content_size large

STANDARD_SCREENSHOT_SHA256="$(shasum -a 256 "$STANDARD_SCREENSHOT" | awk '{print $1}')"
AX5_SCREENSHOT_SHA256="$(shasum -a 256 "$AX5_SCREENSHOT" | awk '{print $1}')"
INFO_PLIST_SHA256="$(shasum -a 256 "$INFO_PLIST" | awk '{print $1}')"
PNG_CONTENT_GUARD_SHA256="$(shasum -a 256 "$PNG_CONTENT_GUARD" | awk '{print $1}')"
for digest in "$STANDARD_SCREENSHOT_SHA256" "$AX5_SCREENSHOT_SHA256" "$INFO_PLIST_SHA256" "$PNG_CONTENT_GUARD_SHA256"; do
  if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Could not derive stable SHA-256 evidence digests." >&2
    exit 17
  fi
done

/usr/bin/python3 - "$ARTIFACTS_DIR/NembraCaptureStandaloneVisualEvidence.json" "$BUILD_IDENTIFIER" "$SOURCE_SHA" "$PROCEDURE_IDENTIFIER" "$BUNDLE_ID" "$RUNTIME_ID" "$DEVICE_TYPE" "$STANDARD_SCREENSHOT_SHA256" "$AX5_SCREENSHOT_SHA256" "$INFO_PLIST_SHA256" "$PNG_CONTENT_GUARD_SHA256" <<'PY'
import json
import sys
(
    output_path,
    build_identifier,
    source_sha,
    procedure_identifier,
    bundle_id,
    runtime_id,
    device_type,
    standard_screenshot_sha256,
    ax5_screenshot_sha256,
    info_plist_sha256,
    png_content_guard_sha256,
) = sys.argv[1:]
record = {
    "schemaVersion": 6,
    "authority": "standalone-capture-simulator-presentation-only",
    "buildIdentifier": build_identifier,
    "sourceCommitSHA": source_sha,
    "tuyaDependencyLockSHA256": "",
    "tuyaDependencyProvenanceClass": "deliberately-absent-public-ci",
    "expectedFieldBuildAuthority": False,
    "procedureIdentifier": procedure_identifier,
    "requiredProcedureSourceVerified": True,
    "procedureBuildRendezvousVerified": True,
    "bundleIdentifier": bundle_id,
    "baselineDevice": "iPhone 12",
    "baselineOS": "iOS 27",
    "simulatorRuntime": runtime_id,
    "simulatorDeviceType": device_type,
    "launchContext": "real standalone bundle; required procedure mapped through Xcode and read back from built app; private dependency provenance absent; inherited SIMCTL_CHILD/NEMBRA_SIMULATION authority rejected before launch",
    "syntheticAuthorityEnvironmentRejected": True,
    "expectedReviewState": "public/unprovisioned root presentation; reviewer must verify fail-closed messaging visually",
    "visualAcceptanceRequiresHumanReview": True,
    "screenshotRenderedContentReadinessVerified": True,
    "screenshotRenderedContentGuard": "capture_visual_png_content_guard.py/v1",
    "screenshotRenderedContentGuardSHA256": png_content_guard_sha256,
    "physicalAuthorityCreated": False,
    "protocolAuthorityCreated": False,
    "screenshots": [
        {"state": "unprovisioned-dark-standard", "relativePath": "screenshots/standalone-unprovisioned-dark-iphone12.png", "sha256": standard_screenshot_sha256},
        {"state": "unprovisioned-dark-accessibility-xxxl", "relativePath": "screenshots/standalone-unprovisioned-dark-iphone12-ax5.png", "sha256": ax5_screenshot_sha256},
    ],
    "infoPlistSHA256": info_plist_sha256,
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '%s\n' \
  "Standalone Nembra Capture visual evidence captured on exact V14 baseline." \
  "Build: $BUILD_IDENTIFIER" \
  "Source: $SOURCE_SHA" \
  "Procedure read back from built app: $PROCEDURE_IDENTIFIER" \
  "Tuya dependency authority: deliberately absent in public CI" \
  "Baseline: $EXPECTED_DEVICE_NAME / iOS 27 Simulator" \
  "Standard screenshot: $STANDARD_SCREENSHOT" \
  "Accessibility XXXL screenshot: $AX5_SCREENSHOT" \
  "Rendered-content guard: $PNG_CONTENT_GUARD_SHA256" \
  "Visual review is still required; this artifact creates no physical/protocol authority."
