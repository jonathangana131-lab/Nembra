from pathlib import Path

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_guided_frozen_visual_evidence.sh").read_text(encoding="utf-8")

required = [
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'item.get("name") == "iPhone 12"',
    'SIMCTL_CHILD_*|NEMBRA_SIMULATION_*)',
    'done < <(compgen -v)',
    'TUYA_DEPENDENCY_LOCK_SHA256=',
    'if [[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'standalone-unprovisioned-dark.png',
    'standalone-unprovisioned-dark-accessibility-xxxl.png',
    '"schemaVersion": 3',
    '"evidenceProfile": "public-unprovisioned-frozen-product-child"',
    '"productionBytesMatchProductParent": True',
    '"procedureBuildProvenanceVerified": False',
    '"expectedFieldBuildAuthority": False',
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
    raise SystemExit("visual evidence must launch the standalone product without fixture arguments")
if 'preferred=[' in script or '"iPhone 17"' in script or '"iPhone 16"' in script:
    raise SystemExit("V14 visual gate must not fall back from the exact iPhone 12 baseline")
if "procedureBuildProvenanceVerified\": True" in script:
    raise SystemExit("public visual evidence must not claim built procedure provenance")
if "expectedFieldBuildAuthority\": True" in script:
    raise SystemExit("public visual evidence must not claim field-build authority")

print("current guided Capture visual evidence source contract: PASS")
