from pathlib import Path

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-field-build-provenance.yml").read_text(encoding="utf-8")

required_script = [
    'EXPECTED_SOURCE_SHA="${EXPECTED_SOURCE_SHA:-}"',
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    'EVIDENCE_PROFILE="${EVIDENCE_PROFILE:-public-unprovisioned}"',
    '[[ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]]',
    'public-unprovisioned)',
    'if [[ -n "$TUYA_DEPENDENCY_LOCK_SHA256" ]]',
    'DEPENDENCY_PROVENANCE_CLASS="deliberately-absent-public-ci"',
    'EXPECTED_FIELD_BUILD_AUTHORITY="false"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]',
    'EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"',
    'xcrun simctl ui "$UDID" appearance dark',
    'xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large',
    'launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID"',
    '"authority": "standalone-capture-simulator-presentation-only"',
    '"evidenceProfile": evidence_profile',
    '"tuyaDependencyLockSHA256": tuya_dependency_lock_sha256 or None',
    '"tuyaDependencyProvenanceClass": dependency_provenance_class',
    '"expectedFieldBuildAuthority": expected_field_build_authority == "true"',
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

if "SIMCTL_CHILD_" not in script or "NEMBRA_SIMULATION_" not in script:
    raise SystemExit("script must reject inherited simulator authority environment before launch")

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
if "--args" in launch_lines[0]:
    raise SystemExit("standalone launch must not inject launch fixtures")

required_workflow = [
    'ref: ${{ github.event.pull_request.head.sha || github.sha }}',
    'CAPTURE_VISUAL_SOURCE_SHA=',
    "dependency_sha=''",
    'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256="$dependency_sha"',
    'test -z "$embedded_dependency"',
    'EVIDENCE_PROFILE=public-unprovisioned',
    'EXPECTED_SOURCE_SHA="$CAPTURE_VISUAL_SOURCE_SHA"',
    'uses: actions/upload-artifact@v4',
]
for needle in required_workflow:
    if needle not in workflow:
        raise SystemExit(f"missing workflow visual-evidence integration contract: {needle}")

for forbidden in [
    "sha='0123456789abcdef0123456789abcdef01234567'",
    "dependency_sha='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'",
]:
    if forbidden in workflow:
        raise SystemExit(f"public visual workflow must not mint synthetic authority: {forbidden}")

build_pos = workflow.find("- name: Build exact-head standalone Simulator app for visual review")
capture_pos = workflow.find("- name: Capture real standalone Simulator visual evidence")
upload_pos = workflow.find("- name: Upload standalone visual evidence")
if min(build_pos, capture_pos, upload_pos) < 0 or not (build_pos < capture_pos < upload_pos):
    raise SystemExit("visual evidence must be captured after the exact-head build and uploaded after capture")

print("capture standalone visual evidence no-fake-authority + accessibility contract: PASS")
