#!/bin/bash
set -euo pipefail

APP_PATH="${APP_PATH:-/tmp/NembraCaptureGuidedVisualDerived/Build/Products/Debug-iphonesimulator/Nembra Capture.app}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${RUNNER_TEMP:-/tmp}/NembraCaptureGuidedFrozenVisualEvidence}"
EXPECTED_VALIDATION_SHA="${EXPECTED_VALIDATION_SHA:-}"
EXPECTED_PRODUCT_PARENT_SHA="${EXPECTED_PRODUCT_PARENT_SHA:-}"
PROCEDURE_SOURCE_CONTRACT_ID="${PROCEDURE_SOURCE_CONTRACT_ID:-ES80-AUTHENTICATED-STATIONARY-v1}"
EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Guided Capture visual evidence requires macOS/CoreSimulator." >&2
  exit 2
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Standalone Capture app was not found at: $APP_PATH" >&2
  exit 3
fi
if [[ ! -x /usr/bin/plutil ]] || ! command -v xcrun >/dev/null 2>&1; then
  echo "plutil and xcrun/CoreSimulator are required." >&2
  exit 4
fi
for sha in "$EXPECTED_VALIDATION_SHA" "$EXPECTED_PRODUCT_PARENT_SHA"; do
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    echo "Expected validation and product-parent identities must be lowercase 40-hex SHAs." >&2
    exit 5
  fi
done

INFO_PLIST="$APP_PATH/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Standalone Capture Info.plist is missing." >&2
  exit 6
fi

BUNDLE_ID="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
BUILD_IDENTIFIER="$(/usr/bin/plutil -extract NembraCaptureBuildIdentifier raw -o - "$INFO_PLIST")"
SOURCE_SHA="$(/usr/bin/plutil -extract NembraCaptureSourceCommitSHA raw -o - "$INFO_PLIST")"
TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$INFO_PLIST" 2>/dev/null || true)"

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected standalone Capture bundle identifier: $BUNDLE_ID" >&2
  exit 7
fi
if [[ "$SOURCE_SHA" != "$EXPECTED_VALIDATION_SHA" ]]; then
  echo "Built app source identity does not match the exact validation head." >&2
  exit 8
fi
EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"
if [[ "$BUILD_IDENTIFIER" != "$EXPECTED_BUILD_IDENTIFIER" ]]; then
  echo "Standalone Capture build identifier does not rendezvous with its source SHA." >&2
  exit 9
fi
if [[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]; then
  echo "Public visual evidence must not carry private Tuya dependency provenance or a shape-only substitute." >&2
  exit 10
fi
if [[ "$PROCEDURE_SOURCE_CONTRACT_ID" != "ES80-AUTHENTICATED-STATIONARY-v1" ]]; then
  echo "Visual evidence procedure source contract is not the canonical stationary procedure." >&2
  exit 11
fi

if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" ]]; then
  echo "Refusing to mix or overwrite prior visual evidence: $ARTIFACTS_DIR" >&2
  exit 12
fi
mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs"

RUNTIME_ID="$({ xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version", "0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || {
  echo "No available iOS 27 Simulator runtime was found." >&2
  exit 13
}

DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys
for item in json.load(sys.stdin)["devicetypes"]:
    if item.get("name") == "iPhone 12":
        print(item["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "V14 visual acceptance requires the iPhone 12 Simulator device type exactly." >&2
  exit 14
}

SIM_NAME="Nembra Capture Frozen Visual ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 5m --style compact --predicate 'process contains[c] "Nembra"' \
    > "$ARTIFACTS_DIR/logs/nembra-capture-system.log" 2>&1 || true
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP_PATH"
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override \
  --time 9:41 \
  --batteryState charged \
  --batteryLevel 82 \
  --wifiBars 3 \
  --cellularMode active \
  --cellularBars 4 >/dev/null 2>&1 || true

# simctl forwards SIMCTL_CHILD_* into the launched process. Public presentation evidence must
# fail closed rather than inherit any synthetic account/device or scenario authority.
while IFS= read -r variable_name; do
  case "$variable_name" in
    SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)
      echo "Refusing visual evidence with inherited synthetic authority: $variable_name" >&2
      exit 15
      ;;
  esac
done < <(compgen -v)

launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID" | tee "$ARTIFACTS_DIR/logs/launch.log")"
pid="${launch_output##*: }"
if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
  echo "Could not parse standalone Capture process ID from: $launch_output" >&2
  exit 16
fi
sleep 2
if ! kill -0 "$pid" >/dev/null 2>&1; then
  echo "Standalone Nembra Capture exited before visual evidence could be captured." >&2
  exit 17
fi

STANDARD_SCREENSHOT="$ARTIFACTS_DIR/screenshots/standalone-unprovisioned-dark.png"
xcrun simctl io "$UDID" screenshot "$STANDARD_SCREENSHOT"
if [[ ! -s "$STANDARD_SCREENSHOT" ]]; then
  echo "Standard Capture screenshot was not created." >&2
  exit 18
fi

xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
sleep 1
AX_SCREENSHOT="$ARTIFACTS_DIR/screenshots/standalone-unprovisioned-dark-accessibility-xxxl.png"
xcrun simctl io "$UDID" screenshot "$AX_SCREENSHOT"
if [[ ! -s "$AX_SCREENSHOT" ]]; then
  echo "Accessibility XXXL Capture screenshot was not created." >&2
  exit 19
fi
xcrun simctl ui "$UDID" content_size large >/dev/null 2>&1 || true

STANDARD_SHA256="$(shasum -a 256 "$STANDARD_SCREENSHOT" | awk '{print $1}')"
AX_SHA256="$(shasum -a 256 "$AX_SCREENSHOT" | awk '{print $1}')"
INFO_PLIST_SHA256="$(shasum -a 256 "$INFO_PLIST" | awk '{print $1}')"
for digest in "$STANDARD_SHA256" "$AX_SHA256" "$INFO_PLIST_SHA256"; do
  if [[ ! "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Could not derive stable SHA-256 evidence digests." >&2
    exit 20
  fi
done

/usr/bin/python3 - \
  "$ARTIFACTS_DIR/NembraCaptureGuidedFrozenVisualEvidence.json" \
  "$BUILD_IDENTIFIER" \
  "$SOURCE_SHA" \
  "$EXPECTED_PRODUCT_PARENT_SHA" \
  "$PROCEDURE_SOURCE_CONTRACT_ID" \
  "$BUNDLE_ID" \
  "$RUNTIME_ID" \
  "$DEVICE_TYPE" \
  "$STANDARD_SHA256" \
  "$AX_SHA256" \
  "$INFO_PLIST_SHA256" <<'PY'
import json
import sys

(
    output_path,
    build_identifier,
    validation_sha,
    product_parent_sha,
    procedure_source_contract_id,
    bundle_id,
    runtime_id,
    device_type,
    standard_sha256,
    ax_sha256,
    info_plist_sha256,
) = sys.argv[1:]

record = {
    "schemaVersion": 3,
    "authority": "standalone-capture-simulator-presentation-only",
    "evidenceProfile": "public-unprovisioned-frozen-product-child",
    "validationSourceCommitSHA": validation_sha,
    "productParentCommitSHA": product_parent_sha,
    "productionBytesMatchProductParent": True,
    "buildIdentifier": build_identifier,
    "bundleIdentifier": bundle_id,
    "procedureSourceContractIdentifier": procedure_source_contract_id,
    "procedureBuildProvenanceVerified": False,
    "tuyaDependencyLockSHA256": None,
    "tuyaDependencyProvenanceClass": "deliberately-absent-public-ci",
    "expectedFieldBuildAuthority": False,
    "simulatorRuntime": runtime_id,
    "simulatorDeviceType": device_type,
    "syntheticAuthorityEnvironmentRejected": True,
    "visualAcceptanceRequiresHumanReview": True,
    "physicalAuthorityCreated": False,
    "protocolAuthorityCreated": False,
    "expectedReviewState": "real public/unprovisioned Capture root; no account/device fixture; no field-build authority",
    "screenshots": [
        {
            "state": "unprovisioned-dark-standard",
            "relativePath": "screenshots/standalone-unprovisioned-dark.png",
            "sha256": standard_sha256,
        },
        {
            "state": "unprovisioned-dark-accessibility-xxxl",
            "relativePath": "screenshots/standalone-unprovisioned-dark-accessibility-xxxl.png",
            "sha256": ax_sha256,
        },
    ],
    "infoPlistSHA256": info_plist_sha256,
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

printf '%s\n' \
  "Frozen guided Capture visual evidence captured." \
  "Validation source: $SOURCE_SHA" \
  "Frozen product parent: $EXPECTED_PRODUCT_PARENT_SHA" \
  "Procedure source contract: $PROCEDURE_SOURCE_CONTRACT_ID (build provenance not verified here)" \
  "Standard screenshot: $STANDARD_SCREENSHOT" \
  "Accessibility XXXL screenshot: $AX_SCREENSHOT" \
  "Human review is required; this evidence creates no field, protocol, or physical authority."
