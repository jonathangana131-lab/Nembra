from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")

required = [
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'EVIDENCE_PROFILE="${EVIDENCE_PROFILE:-provenance-stamped}"',
    'EXPECTED_SOURCE_SHA="${EXPECTED_SOURCE_SHA:-}"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]',
    'EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"',
    '"$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA"',
    'public-unprovisioned)',
    '[[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'DEPENDENCY_PROVENANCE_CLASS="deliberately-absent-public-ci"',
    'EXPECTED_FIELD_BUILD_AUTHORITY="false"',
    'SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)',
    'done < <(compgen -v)',
    'launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID"',
    'xcrun simctl io "$UDID" screenshot "$SCREENSHOT"',
    '"schemaVersion": 2',
    '"syntheticAuthorityEnvironmentRejected": True',
    '"visualAcceptanceRequiresHumanReview": True',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"expectedFieldBuildAuthority": expected_field_build_authority == "true"',
    '"tuyaDependencyLockSHA256": tuya_dependency_lock_sha256 or None',
]
for needle in required:
    if needle not in script:
        raise SystemExit(f"missing standalone visual-evidence contract: {needle}")

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
launch_line = launch_lines[0]
if "--args" in launch_line or "SIMCTL_CHILD_" in launch_line or "NEMBRA_SIMULATION_" in launch_line:
    raise SystemExit("standalone launch must not inject synthetic authority or launch fixtures")

for forbidden in ("connectBLE", "writeValue", "publishDps", "publishDpsWithSuccess", "local_key"):
    if re.search(rf"\b{re.escape(forbidden)}\b", "\n".join(active_lines)):
        raise SystemExit(f"visual-evidence harness must not contain scooter/protocol action: {forbidden}")

public_case = script.split('public-unprovisioned)', 1)[1].split(';;', 1)[0]
if '[[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]' not in public_case:
    raise SystemExit("public-unprovisioned profile must reject any dependency fingerprint")
if 'EXPECTED_FIELD_BUILD_AUTHORITY="false"' not in public_case:
    raise SystemExit("public-unprovisioned profile must record fail-closed field-build authority")

print("capture standalone visual evidence source contract: PASS")