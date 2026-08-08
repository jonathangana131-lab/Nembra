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

CAPTURE_BUILD_COMMIT_SHA="$(git rev-parse --verify HEAD^{commit})"
if [[ ! "$CAPTURE_BUILD_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Capture build identity requires an exact 40-hex Git commit; got: $CAPTURE_BUILD_COMMIT_SHA" >&2
  exit 8
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Capture build identity refuses a checkout with tracked-file modifications." >&2
  git status --short --untracked-files=no >&2
  exit 9
fi
CAPTURE_BUILD_IDENTIFIER="Capture Build V14-${CAPTURE_BUILD_COMMIT_SHA:0:12}"
CAPTURE_RECIPE_IDENTIFIER="ES80-FINGERPRINT-v1"
CAPTURE_PROCEDURE_VERSION="V14"

{
  echo "date=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "runner_arch=$(uname -m)"
  echo "capture_build_identifier=$CAPTURE_BUILD_IDENTIFIER"
  echo "capture_build_commit_sha=$CAPTURE_BUILD_COMMIT_SHA"
  echo "capture_recipe_identifier=$CAPTURE_RECIPE_IDENTIFIER"
  echo "capture_procedure_version=$CAPTURE_PROCEDURE_VERSION"
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
  "INFOPLIST_KEY_NembraCaptureBuildIdentifier=$CAPTURE_BUILD_IDENTIFIER" \
  "INFOPLIST_KEY_NembraCaptureBuildCommitSHA=$CAPTURE_BUILD_COMMIT_SHA" \
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

INFO_PLIST="$APP_PATH/Info.plist"
EMBEDDED_BUILD_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
EMBEDDED_BUILD_COMMIT_SHA="$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureBuildCommitSHA' "$INFO_PLIST" 2>/dev/null || true)"
if [[ "$EMBEDDED_BUILD_IDENTIFIER" != "$CAPTURE_BUILD_IDENTIFIER" ]]; then
  echo "Built app did not preserve the exact Capture build identifier." >&2
  exit 10
fi
if [[ "$EMBEDDED_BUILD_COMMIT_SHA" != "$CAPTURE_BUILD_COMMIT_SHA" ]]; then
  echo "Built app did not preserve the exact Capture source commit SHA." >&2
  exit 11
fi

EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST")"
EXECUTABLE_PATH="$APP_PATH/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Expected built executable was not found at $EXECUTABLE_PATH" >&2
  exit 12
fi
EXECUTABLE_SHA256="$(shasum -a 256 "$EXECUTABLE_PATH" | awk '{print $1}')"
if [[ ! "$EXECUTABLE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Could not derive a valid SHA-256 digest for the built executable." >&2
  exit 13
fi

# Keep the exact-executable digest record OUTSIDE the app bundle.
#
# On a signed Apple-platform app, bundle resources participate in the code-signing resource seal,
# while the code signature itself is stored in the Mach-O executable. Embedding a resource that
# contains the hash of the final signed executable would therefore create a self-reference loop:
# the record changes the resource seal/signature, which changes the executable digest recorded by
# that same resource. Simulator uses CODE_SIGNING_ALLOWED=NO, but this harness must not normalize a
# topology that cannot truthfully carry over to the final physical-device build.
EXTERNAL_BUILD_RECORD="$ARTIFACTS_DIR/NembraCaptureExternalBuildRecord.json"
RUNNER_METADATA="$ARTIFACTS_DIR/capture-runner-metadata.json"
python3 - \
  "$EXTERNAL_BUILD_RECORD" \
  "$RUNNER_METADATA" \
  "$CAPTURE_BUILD_IDENTIFIER" \
  "$CAPTURE_BUILD_COMMIT_SHA" \
  "$EXECUTABLE_SHA256" \
  "$CAPTURE_RECIPE_IDENTIFIER" \
  "$CAPTURE_PROCEDURE_VERSION" \
  "$BUNDLE_ID" \
  "${GITHUB_RUN_ID:-local}" \
  "${GITHUB_RUN_ATTEMPT:-0}" <<'PY'
import hashlib
import json
import sys

(
    external_record_path,
    runner_metadata_path,
    build_identifier,
    source_commit_sha,
    executable_sha256,
    recipe_identifier,
    procedure_version,
    bundle_identifier,
    run_id,
    run_attempt,
) = sys.argv[1:]

external_record = {
    "schemaVersion": 1,
    "buildIdentifier": build_identifier,
    "sourceCommitSHA": source_commit_sha,
    "executableSHA256": executable_sha256,
    "experimentRecipeID": recipe_identifier,
    "procedureVersion": procedure_version,
}
external_bytes = (
    json.dumps(external_record, indent=2, sort_keys=True).encode("utf-8") + b"\n"
)
with open(external_record_path, "wb") as handle:
    handle.write(external_bytes)

runner_metadata = {
    "schemaVersion": 1,
    "authority": "external-runner-simulator-provenance-not-field-authorization",
    "externalBuildRecordSHA256": hashlib.sha256(external_bytes).hexdigest(),
    "bundleIdentifier": bundle_identifier,
    "platform": "iOS Simulator",
    "githubRunID": run_id,
    "githubRunAttempt": run_attempt,
}
with open(runner_metadata_path, "w", encoding="utf-8") as handle:
    json.dump(runner_metadata, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

EXTERNAL_BUILD_RECORD_SHA256="$(shasum -a 256 "$EXTERNAL_BUILD_RECORD" | awk '{print $1}')"

printf '%s\n' \
  "capture_executable_sha256=$EXECUTABLE_SHA256" \
  "capture_external_build_record=$EXTERNAL_BUILD_RECORD" \
  "capture_external_build_record_sha256=$EXTERNAL_BUILD_RECORD_SHA256" \
  "capture_runner_metadata=$RUNNER_METADATA" \
  >> "$ARTIFACTS_DIR/environment.txt"

# Assert the final Simulator app was not mutated with a self-referential executable-digest record.
if [[ -e "$APP_PATH/NembraCaptureTrustedBuildRecord.json" || -e "$APP_PATH/NembraCaptureExternalBuildRecord.json" ]]; then
  echo "Executable-digest provenance record must remain external to the built app bundle." >&2
  exit 14
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
