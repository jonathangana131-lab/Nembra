#!/bin/bash
set -euo pipefail

ARTIFACTS_DIR="${ARTIFACTS_DIR:-${RUNNER_TEMP:-/tmp}/NembraCaptureShellVisualMatrix}"
QA_WORK_DIR="${QA_WORK_DIR:-${RUNNER_TEMP:-/tmp}/NembraCaptureShellVisualMatrixWork}"
EXPECTED_DEVICE_NAME="iPhone 12"
EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"
BUNDLE_ID="com.jonathangana131.nembra.capturelearn"
SCENARIO_ENV="NEMBRA_CAPTURE_SHELL_QA_SCENARIO"
ENTRYPOINT_REL="NembraApp/App/NembraCaptureEntrypoint.swift"
FIXTURE_REL="Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/PassiveBluetoothExperimentOneSimulatorQAFixture.swift"

SCENARIOS=(
  stationaryPreflight
  targetConfirmation
  passiveDiscovery
  captureInProgress
  observationHorizonReady
  horizonSealed
  captureComplete
  shareRetry
  foregroundInterrupted
)

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Capture shell visual matrix requires macOS/CoreSimulator." >&2
  exit 2
fi
if ! command -v xcrun >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcrun and xcodebuild are required." >&2
  exit 3
fi
if [[ -e "$ARTIFACTS_DIR" || -L "$ARTIFACTS_DIR" || -e "$QA_WORK_DIR" || -L "$QA_WORK_DIR" ]]; then
  echo "Refusing to mix or overwrite prior shell-matrix state." >&2
  exit 4
fi

SOURCE_SHA="$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')"
if [[ ! "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Exact checkout SHA must be lowercase 40-hex." >&2
  exit 5
fi
if [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "Capture shell matrix requires a clean exact checkout." >&2
  exit 6
fi
if grep -Fq "$SCENARIO_ENV" "$ENTRYPOINT_REL" || grep -Fq 'PassiveBluetoothExperimentOneSimulatorQAFixture' "$ENTRYPOINT_REL"; then
  echo "Shipping Capture entrypoint already contains a simulator-QA injection hook; refusing to build visual evidence." >&2
  exit 7
fi
if ! grep -Fq '#if DEBUG && targetEnvironment(simulator)' "$FIXTURE_REL" \
   || ! grep -Fq 'physicalProcedurePermitted: false' "$FIXTURE_REL" \
   || ! grep -Fq 'mayUseBluetoothTransport: false' "$FIXTURE_REL"; then
  echo "Simulator QA fixture no longer proves the required no-GO/no-transport boundary." >&2
  exit 8
fi

mkdir -p "$ARTIFACTS_DIR/screenshots" "$ARTIFACTS_DIR/logs" "$QA_WORK_DIR"

# The QA app is built from an archive of the exact tracked subject. Only the temporary archive copy
# receives a synthetic @main host; the checked-out shipping source is never mutated.
git archive --format=tar HEAD | tar -xf - -C "$QA_WORK_DIR"
QA_ENTRYPOINT="$QA_WORK_DIR/$ENTRYPOINT_REL"
/usr/bin/python3 - "$QA_ENTRYPOINT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text(encoding="utf-8")
needle = "@main @MainActor\nstruct NembraCaptureApp: App {"
if source.count(needle) != 1:
    raise SystemExit("Shipping Capture @main declaration changed; refusing synthetic QA materialization")
source = source.replace(needle, "@MainActor\nstruct NembraCaptureApp: App {", 1)
source += r'''

#if DEBUG && targetEnvironment(simulator)
@MainActor
private struct CaptureShellVisualQAHost: View {
    private let snapshot: PassiveBluetoothExperimentOneSimulatorQAFixture.Snapshot
    private let coordinator: PassiveBluetoothExperimentOneCoordinator

    init() {
        let environment = ProcessInfo.processInfo.environment
        guard let rawScenario = environment["NEMBRA_CAPTURE_SHELL_QA_SCENARIO"],
              let scenario = PassiveBluetoothExperimentOneSimulatorQAFixture.Scenario(rawValue: rawScenario) else {
            preconditionFailure("Missing or invalid presentation-only Capture shell QA scenario")
        }
        let snapshot = PassiveBluetoothExperimentOneSimulatorQAFixture.snapshot(for: scenario)
        precondition(snapshot.physicalProcedurePermitted == false)
        precondition(snapshot.mayUseBluetoothTransport == false)
        self.snapshot = snapshot
        self.coordinator = try! PassiveBluetoothExperimentOneCoordinator()
    }

    var body: some View {
        NavigationStack {
            ES80CaptureShellView(
                coordinator: coordinator,
                simulatorQASnapshot: snapshot,
                onFreshExperimentRequested: { try PassiveBluetoothExperimentOneCoordinator() }
            )
        }
        .preferredColorScheme(.dark)
    }
}

@main @MainActor
private struct NembraCaptureShellVisualQAApp: App {
    var body: some Scene {
        WindowGroup { CaptureShellVisualQAHost() }
    }
}
#endif
'''
path.write_text(source, encoding="utf-8")
PY

if grep -Fq "$SCENARIO_ENV" "$ENTRYPOINT_REL" || grep -Fq 'PassiveBluetoothExperimentOneSimulatorQAFixture' "$ENTRYPOINT_REL"; then
  echo "Synthetic QA materialization escaped into the shipping checkout." >&2
  exit 9
fi
if ! grep -Fq "$SCENARIO_ENV" "$QA_ENTRYPOINT" \
   || ! grep -Fq 'precondition(snapshot.physicalProcedurePermitted == false)' "$QA_ENTRYPOINT" \
   || ! grep -Fq 'precondition(snapshot.mayUseBluetoothTransport == false)' "$QA_ENTRYPOINT"; then
  echo "Temporary shell-QA host was not materialized with fail-closed guards." >&2
  exit 10
fi

DERIVED_DATA="$QA_WORK_DIR/DerivedData"
(
  cd "$QA_WORK_DIR"
  xcodebuild -project NembraCapture.xcodeproj -scheme 'Nembra Capture' -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO \
    NEMBRA_CAPTURE_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}" \
    NEMBRA_CAPTURE_BUILD_COMMIT_SHA="$SOURCE_SHA" \
    NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="" \
    NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1" \
    build | tee "$ARTIFACTS_DIR/logs/xcodebuild.log"
)
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Nembra Capture.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Temporary Capture shell QA app did not build." >&2
  exit 11
fi

RUNTIME_ID="$({ xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
r=json.load(sys.stdin)["runtimes"]
c=[x for x in r if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]
if not c: raise SystemExit(1)
c.sort(key=lambda x: tuple(int(p) for p in str(x.get("version","0")).split(".") if p.isdigit()), reverse=True)
print(c[0]["identifier"])
'; } 2>/dev/null)" || {
  echo "No iOS 27 Simulator runtime is available." >&2
  exit 12
}
DEVICE_TYPE="$({ xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys
for x in json.load(sys.stdin)["devicetypes"]:
    if x.get("name") == "iPhone 12":
        print(x["identifier"]); raise SystemExit(0)
raise SystemExit(1)
'; } 2>/dev/null)" || {
  echo "The required iPhone 12 Simulator device type is unavailable." >&2
  exit 13
}
if [[ "$DEVICE_TYPE" != "$EXPECTED_DEVICE_TYPE" ]]; then
  echo "Unexpected iPhone 12 Simulator device type: $DEVICE_TYPE" >&2
  exit 14
fi

SIM_NAME="Nembra Capture Shell Matrix ${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process contains[c] "Nembra"' > "$ARTIFACTS_DIR/logs/nembra-capture-shell-system.log" 2>&1 || true
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

capture_one() {
  local scenario="$1"
  local size_label="$2"
  local content_size="$3"
  local screenshot="$ARTIFACTS_DIR/screenshots/${scenario}-${size_label}-dark-iphone12.png"

  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl ui "$UDID" content_size "$content_size"
  local launch_output
  launch_output="$(SIMCTL_CHILD_NEMBRA_CAPTURE_SHELL_QA_SCENARIO="$scenario" xcrun simctl launch "$UDID" "$BUNDLE_ID" | tee -a "$ARTIFACTS_DIR/logs/launch.log")"
  local pid="${launch_output##*: }"
  if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "Could not parse QA process ID for $scenario/$size_label from: $launch_output" >&2
    exit 15
  fi
  sleep 1.5
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Temporary Capture shell QA app exited before $scenario/$size_label screenshot." >&2
    exit 16
  fi
  xcrun simctl io "$UDID" screenshot "$screenshot"
  if [[ ! -s "$screenshot" ]]; then
    echo "Missing shell-matrix screenshot: $screenshot" >&2
    exit 17
  fi
}

for scenario in "${SCENARIOS[@]}"; do
  capture_one "$scenario" standard large
done
for scenario in "${SCENARIOS[@]}"; do
  capture_one "$scenario" accessibility-xxxl accessibility-extra-extra-extra-large
done
xcrun simctl ui "$UDID" content_size large

/usr/bin/python3 - "$ARTIFACTS_DIR/NembraCaptureShellVisualMatrix.json" "$ARTIFACTS_DIR/screenshots" "$SOURCE_SHA" "$RUNTIME_ID" "$DEVICE_TYPE" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

output_path = Path(sys.argv[1])
screenshots_dir = Path(sys.argv[2])
source_sha, runtime_id, device_type = sys.argv[3:]
items = []
for path in sorted(screenshots_dir.glob("*.png")):
    stem = path.name.removesuffix("-dark-iphone12.png")
    if stem.endswith("-accessibility-xxxl"):
        scenario = stem.removesuffix("-accessibility-xxxl")
        content_size = "accessibility-xxxl"
    elif stem.endswith("-standard"):
        scenario = stem.removesuffix("-standard")
        content_size = "standard"
    else:
        raise SystemExit(f"Unexpected screenshot filename: {path.name}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    items.append({
        "scenario": scenario,
        "contentSize": content_size,
        "relativePath": f"screenshots/{path.name}",
        "sha256": digest,
    })
record = {
    "schemaVersion": 1,
    "authority": "temporary-simulator-qa-host-presentation-only",
    "sourceCommitSHA": source_sha,
    "baselineDevice": "iPhone 12",
    "baselineOS": "iOS 27",
    "simulatorRuntime": runtime_id,
    "simulatorDeviceType": device_type,
    "temporaryQARunnerSourceMutation": True,
    "shippingSourceMutation": False,
    "shippingEntrypointFixtureInjectionAbsent": True,
    "fixturePhysicalProcedurePermitted": False,
    "bluetoothTransportUsed": False,
    "physicalAuthorityCreated": False,
    "protocolAuthorityCreated": False,
    "visualAcceptanceRequiresHumanReview": True,
    "screenshots": items,
}
output_path.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

if [[ "$(find "$ARTIFACTS_DIR/screenshots" -type f -name '*.png' | wc -l | tr -d ' ')" != "18" ]]; then
  echo "Capture shell matrix did not produce the required 18 screenshots." >&2
  exit 18
fi
if [[ "$(git rev-parse HEAD | tr '[:upper:]' '[:lower:]')" != "$SOURCE_SHA" ]] \
   || [[ -n "$(git status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "Shipping checkout changed during temporary shell-matrix generation." >&2
  exit 19
fi

printf '%s\n' \
  "Capture shell visual matrix captured from exact source $SOURCE_SHA." \
  "Temporary QA host only; shipping entrypoint remained unchanged." \
  "Baseline: $EXPECTED_DEVICE_NAME / iOS 27 Simulator." \
  "18 screenshots: nine representative states at standard + Accessibility XXXL." \
  "Every fixture remains NO-GO with Bluetooth transport disabled." \
  "Human visual review is required; this evidence creates no physical/protocol authority."
