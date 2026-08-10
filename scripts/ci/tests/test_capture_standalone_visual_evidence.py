from pathlib import Path

root = Path(__file__).resolve().parents[3]
script = (root / "scripts/ci/capture_standalone_visual_evidence.sh").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-field-build-provenance.yml").read_text(encoding="utf-8")

required_script = [
    'EXPECTED_SOURCE_SHA="${EXPECTED_SOURCE_SHA:-}"',
    'EXPECTED_BUNDLE_ID="com.jonathangana131.nembra.capturelearn"',
    '[[ "$SOURCE_SHA" != "$EXPECTED_SOURCE_SHA" ]]',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'preferred=["iPhone 12", "iPhone 17", "iPhone 17 Pro", "iPhone 16"]',
    'EXPECTED_BUILD_IDENTIFIER="capture-v14-${SOURCE_SHA:0:12}"',
    'xcrun simctl ui "$UDID" appearance dark',
    'xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large',
    'launch_output="$(xcrun simctl launch "$UDID" "$BUNDLE_ID"',
    '"authority": "standalone-capture-simulator-presentation-only"',
    '"tuyaDependencyProvenanceVerified": False',
    '"visualAcceptanceRequiresHumanReview": True',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"state": "unprovisioned-dark-accessibility-xxxl"',
]
for needle in required_script:
    if needle not in script:
        raise SystemExit(f"missing standalone visual-evidence contract: {needle}")

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
if "--args" in launch_lines[0]:
    raise SystemExit("standalone launch must not inject launch fixtures")

required_workflow = [
    'ref: ${{ github.event.pull_request.head.sha || github.sha }}',
    'sha="$(git rev-parse HEAD | tr',
    'expected_sha="${{ github.event.pull_request.head.sha || github.sha }}"',
    'EXPECTED_SOURCE_SHA="$sha" scripts/ci/capture_standalone_visual_evidence.sh',
    'uses: actions/upload-artifact@v4',
    'name: Nembra-Capture-Standalone-Visual-Evidence',
    'path: ${{ runner.temp }}/NembraCaptureStandaloneVisualEvidence',
]
for needle in required_workflow:
    if needle not in workflow:
        raise SystemExit(f"missing workflow visual-evidence integration contract: {needle}")

if "sha='0123456789abcdef0123456789abcdef01234567'" in workflow:
    raise SystemExit("workflow must not stamp the visual-evidence app with a synthetic source SHA")

build_pos = workflow.find("- name: Build stamped standalone Simulator app")
capture_pos = workflow.find("- name: Capture standalone Simulator visual evidence")
upload_pos = workflow.find("- name: Upload standalone Simulator visual evidence")
if min(build_pos, capture_pos, upload_pos) < 0 or not (build_pos < capture_pos < upload_pos):
    raise SystemExit("visual evidence must be captured after the stamped build and uploaded after capture")

print("capture standalone visual evidence source + workflow contract: PASS")
