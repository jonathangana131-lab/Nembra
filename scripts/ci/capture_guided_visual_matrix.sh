#!/bin/bash
set -euo pipefail

APP_PATH="${APP_PATH:-/tmp/NembraCaptureGuidedVisualDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${RUNNER_TEMP:-/tmp}/NembraCaptureGuidedVisualMatrix}"
EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
EXPECTED_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1"
EXPECTED_DEVICE_NAME="iPhone 12"
EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"

[[ "$(uname -s)" == "Darwin" ]] || { echo "guided visual matrix requires macOS/CoreSimulator" >&2; exit 2; }
[[ -d "$APP_PATH" ]] || { echo "standalone Capture app missing: $APP_PATH" >&2; exit 3; }
command -v xcrun >/dev/null 2>&1 || { echo "xcrun is required" >&2; exit 4; }
[[ ! -e "$ARTIFACTS_DIR" ]] || { echo "refusing to overwrite visual evidence: $ARTIFACTS_DIR" >&2; exit 5; }
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs"

INFO_PLIST="$APP_PATH/Info.plist"
BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$INFO_PLIST")"
SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$INFO_PLIST")"
PROCEDURE_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier raw -o - "$INFO_PLIST")"
TUYA_LOCK="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$INFO_PLIST" 2>/dev/null || true)"
[[ "$BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || { echo "unexpected bundle id: $BUNDLE_ID" >&2; exit 6; }
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid source SHA" >&2; exit 7; }
[[ "$PROCEDURE_IDENTIFIER" == "$EXPECTED_PROCEDURE_IDENTIFIER" ]] || { echo "procedure mismatch" >&2; exit 8; }
[[ -z "$TUYA_LOCK" ]] || { echo "guided presentation fixture must not carry private Tuya dependency authority" >&2; exit 9; }
[[ "$BUILD_IDENTIFIER" == "capture-v14-${SOURCE_SHA:0:12}" ]] || { echo "build/source rendezvous failed" >&2; exit 10; }
[[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" == "$SOURCE_SHA" ]] || { echo "checkout/app source mismatch" >&2; exit 11; }

# Refuse unrelated inherited synthetic-authority environments. This harness creates exactly one
# visual-only child variable per launch below and never exposes a general simulation authority.
while IFS= read -r variable_name; do
  case "$variable_name" in
    NEMBRA_SIMULATION_*|SIMCTL_CHILD_NEMBRA_SIMULATION_*|SIMCTL_CHILD_NEMBRA_CAPTURE_GUIDED_VISUAL_STATE)
      echo "refusing inherited synthetic/fixture authority: $variable_name" >&2
      exit 12
      ;;
  esac
done < <(compgen -v)

RUNTIME_ID="$({ xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || { echo "no iOS 27 Simulator runtime" >&2; exit 13; }
DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys
for x in json.load(sys.stdin)["devicetypes"]:
    if x.get("name") == "iPhone 12": print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || { echo "required iPhone 12 Simulator device type unavailable" >&2; exit 14; }
[[ "$DEVICE_TYPE" == "$EXPECTED_DEVICE_TYPE" ]] || { echo "unexpected device type: $DEVICE_TYPE" >&2; exit 15; }

SIM_NAME="Nembra Guided Visual ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 8m --style compact --predicate 'process contains[c] "Nembra"' > "$ARTIFACTS_DIR/logs/nembra-guided-system.log" 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 82 --wifiBars 3 --cellularMode active --cellularBars 4 >/dev/null 2>&1 || true
xcrun simctl ui "$UDID" appearance dark
xcrun simctl ui "$UDID" content_size large

capture_state() {
  local state="$1"
  local suffix="$2"
  local content_size="$3"
  local screenshot="$ARTIFACTS_DIR/screenshots/${state}-${suffix}-iphone12.png"
  local launch_log="$ARTIFACTS_DIR/logs/${state}-${suffix}-launch.log"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size "$content_size"
  SIMCTL_CHILD_NEMBRA_CAPTURE_GUIDED_VISUAL_STATE="$state" \
    xcrun simctl launch "$UDID" "$BUNDLE_ID" > "$launch_log"
  sleep 2
  xcrun simctl io "$UDID" screenshot "$screenshot"
  [[ -s "$screenshot" ]] || { echo "screenshot missing for $state/$suffix" >&2; exit 16; }
  printf '%s\t%s\t%s\n' "$state" "$suffix" "$screenshot" >> "$ARTIFACTS_DIR/screenshot-index.tsv"
}

# Standard matrix covers every flagship guided rung plus a stopped state. Accessibility XXXL is
# concentrated on the two high-density progress surfaces whose reflow is a specific V14 contract.
capture_state correlation-off1 standard large
capture_state correlation-off1 ax5 accessibility-extra-extra-extra-large
capture_state correlated-confirm standard large
capture_state secure-link standard large
capture_state authenticating standard large
capture_state observing standard large
capture_state observing ax5 accessibility-extra-extra-extra-large
capture_state failed-recovery standard large
capture_state accepted standard large
xcrun simctl ui "$UDID" content_size large

/usr/bin/python3 - "$ARTIFACTS_DIR" "$BUILD_IDENTIFIER" "$SOURCE_SHA" "$PROCEDURE_IDENTIFIER" "$BUNDLE_ID" "$RUNTIME_ID" "$DEVICE_TYPE" <<'PY'
import hashlib, json, sys
from pathlib import Path

root = Path(sys.argv[1])
build_identifier, source_sha, procedure_identifier, bundle_id, runtime_id, device_type = sys.argv[2:]
shots=[]
for line in (root / "screenshot-index.tsv").read_text().splitlines():
    state, size_class, raw_path = line.split("\t")
    path=Path(raw_path)
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    shots.append({
        "state": state,
        "sizeClass": size_class,
        "relativePath": str(path.relative_to(root)),
        "sha256": digest,
    })
expected={
    ("correlation-off1","standard"), ("correlation-off1","ax5"),
    ("correlated-confirm","standard"), ("secure-link","standard"),
    ("authenticating","standard"), ("observing","standard"), ("observing","ax5"),
    ("failed-recovery","standard"), ("accepted","standard"),
}
assert {(x["state"],x["sizeClass"]) for x in shots} == expected
record={
    "schemaVersion": 1,
    "authority": "guided-capture-simulator-presentation-only",
    "buildIdentifier": build_identifier,
    "sourceCommitSHA": source_sha,
    "procedureIdentifier": procedure_identifier,
    "bundleIdentifier": bundle_id,
    "tuyaDependencyLockSHA256": "",
    "baselineDevice": "iPhone 12",
    "baselineOS": "iOS 27",
    "simulatorRuntime": runtime_id,
    "simulatorDeviceType": device_type,
    "fixtureEnvironmentKey": "NEMBRA_CAPTURE_GUIDED_VISUAL_STATE",
    "fixtureCompileBoundary": "targetEnvironment(simulator)",
    "fixtureAuthorityCreated": False,
    "protocolAuthorityCreated": False,
    "physicalAuthorityCreated": False,
    "visualAcceptanceRequiresHumanReview": True,
    "expectedReview": "Open every PNG. Review stage hierarchy, clipping, outdoor-readable contrast, action affordance, stopped-state failure clarity, and Accessibility XXXL recomposition. Simulator fixture values are presentation-only and never telemetry/protocol/physical evidence.",
    "screenshots": shots,
}
(root / "NembraCaptureGuidedVisualMatrix.json").write_text(json.dumps(record, indent=2, sort_keys=True)+"\n")
PY

shasum -a 256 "$INFO_PLIST" > "$ARTIFACTS_DIR/Info.plist.sha256"
echo "guided Capture visual matrix captured; human PNG review still required"
