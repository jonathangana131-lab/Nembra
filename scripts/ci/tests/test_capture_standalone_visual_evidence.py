from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-standalone-visual-evidence.yml").read_text(encoding="utf-8")

required_script = [
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'EXPECTED_PROCEDURE_IDENTIFIER="ES80-AUTHENTICATED-STATIONARY-v1"',
    'EXPECTED_DEVICE_NAME="iPhone 12"',
    'EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'if x.get("name") == "iPhone 12"',
    'no newer-device fallback may satisfy the V14 baseline',
    'TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$INFO_PLIST" 2>/dev/null || true)"',
    '[[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'Public standalone visual evidence must not carry Tuya dependency authority',
    'EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"',
    'CHECKOUT_SHA="$(git rev-parse HEAD',
    '[[ "$SOURCE_SHA" != "$CHECKOUT_SHA" ]]',
    'static let requiredFieldProcedureIdentifier = \\"$EXPECTED_PROCEDURE_IDENTIFIER\\"',
    'SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)',
    'done < <(compgen -v)',
    'xcrun simctl ui "$UDID" appearance dark',
    'xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large',
    'xcrun simctl ui "$UDID" content_size large',
    'launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID"',
    'xcrun simctl io "$UDID" screenshot "$STANDARD_SCREENSHOT"',
    'xcrun simctl io "$UDID" screenshot "$AX5_SCREENSHOT"',
    'standalone-unprovisioned-dark-iphone12.png',
    'standalone-unprovisioned-dark-iphone12-ax5.png',
    '"tuyaDependencyLockSHA256": ""',
    '"tuyaDependencyProvenanceClass": "deliberately-absent-public-ci"',
    '"expectedFieldBuildAuthority": False',
    '"baselineDevice": "iPhone 12"',
    '"baselineOS": "iOS 27"',
    '"procedureIdentifier": procedure_identifier',
    '"requiredProcedureSourceVerified": True',
    '"procedureBuildRendezvousVerified": True',
    '"syntheticAuthorityEnvironmentRejected": True',
    '"visualAcceptanceRequiresHumanReview": True',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"state": "unprovisioned-dark-standard"',
    '"state": "unprovisioned-dark-accessibility-xxxl"',
]
for needle in required_script:
    if needle not in script:
        raise SystemExit(f"missing standalone visual-evidence contract: {needle}")

required_workflow = [
    'branches:',
    '- validation/v14-capture-visual-f3ec-sol',
    'static let requiredFieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"',
    'procedureIdentifier == Self.requiredFieldProcedureIdentifier',
    'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";',
    'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure"',
    'plutil -extract NembraCaptureProcedureIdentifier',
    'test -z "$embedded_dependency"',
    'uses: actions/upload-artifact@v4',
]
for needle in required_workflow:
    if needle not in workflow:
        raise SystemExit(f"missing current visual workflow contract: {needle}")

for forbidden_fallback in ('"iPhone 17"', '"iPhone 17 Pro"', '"iPhone 16"', '"iPhone 16 Plus"'):
    if forbidden_fallback in script:
        raise SystemExit(f"newer-device fallback cannot satisfy the iPhone 12 visual baseline: {forbidden_fallback}")

if re.search(r"dependency_sha=['\"][0-9a-f]{64}['\"]", script + "\n" + workflow):
    raise SystemExit("public visual gate must not synthesize a shape-valid Tuya dependency fingerprint")

active_lines = [
    line.strip()
    for line in script.splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
for line in active_lines:
    if re.match(r"^(SIMCTL_CHILD_|NEMBRA_SIMULATION_)[A-Za-z0-9_]*=", line):
        raise SystemExit(f"standalone visual evidence must not assign synthetic app authority: {line}")

launch_lines = [line for line in active_lines if "xcrun simctl launch" in line]
if len(launch_lines) != 1:
    raise SystemExit(f"expected exactly one real standalone launch, found {len(launch_lines)}")
if "--args" in launch_lines[0] or "SIMCTL_CHILD_" in launch_lines[0] or "NEMBRA_SIMULATION_" in launch_lines[0]:
    raise SystemExit("standalone launch must not inject synthetic authority or launch fixtures")

for forbidden in ("connectBLE", "writeValue", "publishDps", "publishDpsWithSuccess", "local_key"):
    if re.search(rf"\b{re.escape(forbidden)}\b", "\n".join(active_lines)):
        raise SystemExit(f"visual-evidence harness must not contain scooter/protocol action: {forbidden}")

print("capture standalone visual evidence current identity contract: PASS")
