from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-standalone-visual-evidence.yml").read_text(encoding="utf-8")
identity = (root / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
project = (root / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")

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
    'xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large',
    '"requiredProcedureSourceVerified": True',
    '"procedureBuildRendezvousVerified": True',
    '"expectedFieldBuildAuthority": False',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
]:
    if needle not in script:
        raise SystemExit(f"missing visual truth contract: {needle}")

for needle in [
    'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=""',
    'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure"',
    'procedureIdentifier == Self.requiredFieldProcedureIdentifier',
    "assert r['schemaVersion']==6",
]:
    if needle not in workflow:
        raise SystemExit(f"missing workflow contract: {needle}")

if re.search(r"dependency_sha=['\"][0-9a-f]{64}['\"]", script + workflow):
    raise SystemExit("public visual QA must not synthesize dependency authority")
if any(x in script for x in ("connectBLE", "writeValue", "publishDps", "publishDpsWithSuccess", "local_key")):
    raise SystemExit("visual harness contains a forbidden scooter/protocol action")

active = [x.strip() for x in script.splitlines() if x.strip() and not x.lstrip().startswith('#')]
launch = [x for x in active if 'xcrun simctl launch' in x]
if len(launch) != 1 or '--args' in launch[0]:
    raise SystemExit("visual harness must launch exactly one unfixtureized standalone app")

print("capture standalone visual evidence current identity contract: PASS")
