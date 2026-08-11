from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-standalone-visual-evidence.yml").read_text(encoding="utf-8")
identity = (root / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
project = (root / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")

guard_path = root / "scripts/ci/capture_visual_png_content_guard.py"
if not guard_path.is_file():
    raise SystemExit("missing fail-closed rendered-content PNG guard")

for needle in [
    'static let requiredFieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"',
    'procedureIdentifier == Self.requiredFieldProcedureIdentifier',
]:
    if needle not in identity:
        raise SystemExit(f"missing required-vs-built procedure contract: {needle}")

mapping = 'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";'
if project.count(mapping) != 2:
    raise SystemExit(f"expected exactly two procedure project mappings, found {project.count(mapping)}")

for needle in [
    'EXPECTED_DEVICE_NAME="iPhone 12"',
    'EXPECTED_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-12"',
    'static let requiredFieldProcedureIdentifier = \\"$EXPECTED_PROCEDURE_IDENTIFIER\\"',
    '[[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)',
    'PNG_CONTENT_GUARD="$ROOT_DIR/scripts/ci/capture_visual_png_content_guard.py"',
    'MAX_SCREENSHOT_ATTEMPTS=40',
    'SCREENSHOT_RETRY_SECONDS=0.25',
    'capture_ready_screenshot() {',
    '/usr/bin/python3 "$PNG_CONTENT_GUARD" "$pending_path" --label "$label attempt $attempt/$MAX_SCREENSHOT_ATTEMPTS"',
    'capture_ready_screenshot "$STANDARD_SCREENSHOT" "Standard iPhone 12 Capture root"',
    'xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large',
    'xcrun simctl terminate "$UDID" "$BUNDLE_ID"',
    'launch_standalone_capture append',
    'capture_ready_screenshot "$AX5_SCREENSHOT" "Accessibility XXXL iPhone 12 Capture root"',
    '"requiredProcedureSourceVerified": True',
    '"procedureBuildRendezvousVerified": True',
    '"expectedFieldBuildAuthority": False',
    '"screenshotRenderedContentReadinessVerified": True',
    '"screenshotRenderedContentGuard": "capture_visual_png_content_guard.py/v1"',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
]:
    if needle not in script:
        raise SystemExit(f"missing visual truth contract: {needle}")

for forbidden in [
    'sleep 2',
    'sleep 1',
]:
    if forbidden in script:
        raise SystemExit(f"visual readiness must not be authorized by a fixed launch delay: {forbidden}")

for needle in [
    '- scripts/ci/capture_visual_png_content_guard.py',
    '- scripts/ci/tests/test_capture_visual_png_content_guard.py',
    '/usr/bin/python3 scripts/ci/tests/test_capture_visual_png_content_guard.py',
    'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=""',
    'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure"',
    'procedureIdentifier == Self.requiredFieldProcedureIdentifier',
    "assert r['schemaVersion']==6",
    "assert r['screenshotRenderedContentReadinessVerified'] is True",
    "assert r['screenshotRenderedContentGuard']=='capture_visual_png_content_guard.py/v1'",
    "assert re.fullmatch(r'[0-9a-f]{64}', r['screenshotRenderedContentGuardSHA256'])",
    'if: always()',
]:
    if needle not in workflow:
        raise SystemExit(f"missing workflow contract: {needle}")

if re.search(r"dependency_sha=['\"][0-9a-f]{64}['\"]", script + workflow):
    raise SystemExit("public visual QA must not synthesize dependency authority")
if any(x in script for x in ("connectBLE", "writeValue", "publishDps", "publishDpsWithSuccess", "local_key")):
    raise SystemExit("visual harness contains a forbidden scooter/protocol action")

active = [x.strip() for x in script.splitlines() if x.strip() and not x.lstrip().startswith('#')]
launch = [x for x in active if 'xcrun simctl launch' in x]
if len(launch) != 2 or any('--args' in line for line in launch):
    raise SystemExit("visual harness must launch only the unfixtureized standalone app for standard and AX5 evidence")

print("capture standalone visual evidence current identity/readiness contract: PASS")
