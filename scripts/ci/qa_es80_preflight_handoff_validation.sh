#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

EXPECTED_PRODUCT="aae86cc243a48dd0993db4ca9c00f0a4284bee85"
EXPECTED_PATHS=".github/workflows/qa-es80-preflight-handoff-aae86-gpt56.yml
scripts/ci/qa_es80_preflight_handoff_validation.sh"

if ! git merge-base --is-ancestor "$EXPECTED_PRODUCT" HEAD; then
  echo "Validation head is not descended from exact #1290 product candidate $EXPECTED_PRODUCT" >&2
  exit 2
fi
changed="$(git diff --name-only "$EXPECTED_PRODUCT" HEAD | sort)"
printf 'Validation-only committed delta from %s:\n%s\n' "$EXPECTED_PRODUCT" "$changed"
if [[ "$changed" != "$EXPECTED_PATHS" ]]; then
  echo "Validation branch contains a non-validation committed delta." >&2
  exit 3
fi

python3 - <<'PY'
from pathlib import Path

path = Path("NembraUITests/ES80ResearchCaptureUITests.swift")
source = path.read_text(encoding="utf-8")
old = '''        XCTAssertTrue(app.buttons["Charger Disconnected"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Stationary Preflight"
'''
new = '''        let disconnected = app.buttons["es80.capture.preflight.charger-disconnected"]
        XCTAssertTrue(disconnected.waitForExistence(timeout: 3))
        disconnected.tap()

        let continueButton = app.buttons["es80.capture.preflight.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture-shell"].waitForExistence(timeout: 5),
            "Accepted stationary preflight must enter the real Capture shell."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["es80.capture.simulator-qa"].waitForExistence(timeout: 3),
            "The exact synthetic QA fixture must survive the preflight handoff."
        )
        XCTAssertTrue(
            app.staticTexts["OFF 1 / READY"].waitForExistence(timeout: 3),
            "The stationaryPreflight fixture must retain its first-powered-off phase after handoff."
        )
        XCTAssertTrue(app.staticTexts["Scooter OFF"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["es80.capture.field-no-go"].exists)
        XCTAssertFalse(app.buttons["Vehicle controls"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Nembra Capture V14 — SIMULATOR QA — Preflight Handoff OFF1"
'''
if source.count(old) != 1:
    raise SystemExit("stationary-preflight UI test block changed unexpectedly")
path.write_text(source.replace(old, new), encoding="utf-8")
PY

plutil -lint Nembra.xcodeproj/project.pbxproj
scripts/validate_pbxproj_references.py
xcodebuild -version

ARTIFACTS_DIR="$ROOT/Artifacts/ES80PreflightHandoff"
DERIVED_DATA="${RUNNER_TEMP:-/tmp}/NembraES80HandoffDerivedData"
mkdir -p "$ARTIFACTS_DIR/logs" "$ARTIFACTS_DIR/test-attachments"

RUNTIME_ID="$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable", True) and str(x.get("identifier", "")).startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")]; r.sort(key=lambda x: str(x.get("version", "")), reverse=True); print(r[0]["identifier"])')"
DEVICE_TYPE="$(xcrun simctl list devicetypes -j | python3 -c 'import json,sys; i=json.load(sys.stdin)["devicetypes"]; p=["iPhone 12","iPhone 17","iPhone 17 Pro","iPhone 16"]; print(next(x["identifier"] for n in p for x in i if x.get("name")==n))')"
UDID="$(xcrun simctl create "Nembra ES80 Handoff ${GITHUB_RUN_ID:-local}" "$DEVICE_TYPE" "$RUNTIME_ID")"
cleanup() {
  xcrun simctl spawn "$UDID" log show --last 10m --style compact --predicate 'process == "Nembra"' > "$ARTIFACTS_DIR/logs/nembra-system.log" 2>&1 || true
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
  xcrun simctl delete "$UDID" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

RESULT_BUNDLE="$ARTIFACTS_DIR/PreflightHandoff.xcresult"
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
  -only-testing:NembraUITests/ES80ResearchCaptureUITests/testV14SimulatorQARendersStationaryPreflightWithoutPromotingFieldGo \
  CODE_SIGNING_ALLOWED=NO \
  test | tee "$ARTIFACTS_DIR/logs/xcodebuild-focused-handoff.log"
STATUS=${PIPESTATUS[0]}
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$ARTIFACTS_DIR/test-attachments" \
    > "$ARTIFACTS_DIR/logs/xcresult-attachments.log" 2>&1 || true
  find "$ARTIFACTS_DIR/test-attachments" -type f -print | sort > "$ARTIFACTS_DIR/test-attachments.txt" || true
fi

exit "$STATUS"
