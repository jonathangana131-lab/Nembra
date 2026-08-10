from pathlib import Path

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_guided_frozen_visual_evidence.sh").read_text(encoding="utf-8")

required = [
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'item.get("name") == "iPhone 12"',
    'SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)',
    'done < <(compgen -v)',
    'if [[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'standalone-unprovisioned-dark.png',
    'standalone-unprovisioned-dark-accessibility-xxxl.png',
    '"schemaVersion": 3',
    '"evidenceProfile": "public-unprovisioned-current-product-child"',
    '"productionBytesMatchProductParent": True',
    '"procedureBuildProvenanceVerified": False',
    '"expectedFieldBuildAuthority": False',
    '"simulatorDeviceName": "iPhone 12"',
    '"syntheticAuthorityEnvironmentRejected": True',
    '"visualAcceptanceRequiresHumanReview": True',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
]
for needle in required:
    if needle not in script:
        raise SystemExit(f"missing current visual-evidence contract: {needle}")

active = [line.strip() for line in script.splitlines() if line.strip() and not line.lstrip().startswith("#")]
launch_lines = [line for line in active if "xcrun simctl launch" in line]
if len(launch_lines) != 1:
    raise SystemExit(f"expected exactly one standalone launch, found {len(launch_lines)}")
if "--args" in launch_lines[0]:
    raise SystemExit("visual evidence must launch without fixture arguments")
if '"iPhone 17"' in script or '"iPhone 16"' in script or "procedureBuildProvenanceVerified\": True" in script or "expectedFieldBuildAuthority\": True" in script:
    raise SystemExit("visual evidence relaxed an exact baseline or authority boundary")

print("exact-current guided Capture visual evidence source contract: PASS")
