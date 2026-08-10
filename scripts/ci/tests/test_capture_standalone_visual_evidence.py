from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")

required = [
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'EXPECTED_SOURCE_SHA="${EXPECTED_SOURCE_SHA:-}"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]',
    'TUYA_DEPENDENCY_LOCK_SHA256="$(/usr/bin/plutil -extract NembraCaptureTuyaDependencyLockSHA256 raw -o - "$INFO_PLIST")"',
    'TUYA_DEPENDENCY_PROVENANCE_AUTHORITY="${TUYA_DEPENDENCY_PROVENANCE_AUTHORITY:-simulator-placeholder-only}"',
    '[[ ! "$EXPECTED_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]',
    '[[ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]]',
    '[[ "$TUYA_DEPENDENCY_PROVENANCE_AUTHORITY" != "simulator-placeholder-only" ]]',
    '[[ ! "$TUYA_DEPENDENCY_LOCK_SHA256" =~ ^[0-9a-f]{64}$ ]]',
    'EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"',
    'launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID"',
    'xcrun simctl io "$UDID" screenshot "$SCREENSHOT"',
    '"visualAcceptanceRequiresHumanReview": True',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"tuyaDependencyProvenanceAuthority": tuya_dependency_provenance_authority',
]
for needle in required:
    if needle not in script:
        raise SystemExit(f"missing standalone visual-evidence contract: {needle}")

if "GITHUB_SHA" in script:
    raise SystemExit("visual evidence must bind to explicit expected PR head, not pull_request GITHUB_SHA merge-ref semantics")

if "SIMCTL_CHILD_" not in script or "NEMBRA_SIMULATION_" not in script:
    raise SystemExit("script must explicitly document that no simulator authority environment is injected")

active_lines = [
    line.strip()
    for line in script.splitlines()
    if line.strip() and not line.lstrip().startswith("#")
]
for line in active_lines:
    if line.startswith("SIMCTL_CHILD_") or line.startswith("NEMBRA_SIMULATION_"):
        raise SystemExit(f"standalone visual evidence must not inject synthetic app authority: {line}")

launch_lines = [line for line in active_lines if "xcrun simctl launch" in line]
if len(launch_lines) != 1:
    raise SystemExit(f"expected exactly one real standalone launch, found {len(launch_lines)}")
launch_line = launch_lines[0]
if "--args" in launch_line or "SIMCTL_CHILD_" in launch_line or "NEMBRA_SIMULATION_" in launch_line:
    raise SystemExit("standalone launch must not inject synthetic authority or launch fixtures")

for forbidden in ("connectBLE", "writeValue", "publishDps", "publishDpsWithSuccess", "local_key"):
    if re.search(rf"\b{re.escape(forbidden)}\b", "\n".join(active_lines)):
        raise SystemExit(f"visual-evidence harness must not contain scooter/protocol action: {forbidden}")

print("capture standalone visual evidence source contract: PASS")
