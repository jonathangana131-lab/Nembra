from pathlib import Path
import re

root = Path(__file__).resolve().parents[3]
runner = (root / "scripts/ci/capture_standalone_visual_evidence.py").read_text(encoding="utf-8")
workflow = (root / ".github/workflows/capture-standalone-visual-evidence.yml").read_text(encoding="utf-8")
identity = (root / "NembraApp/App/NembraCaptureBuildIdentity.swift").read_text(encoding="utf-8")
project = (root / "NembraCapture.xcodeproj/project.pbxproj").read_text(encoding="utf-8")

for needle in [
    'static let requiredFieldProcedureIdentifier = "ES80-AUTHENTICATED-STATIONARY-v1"',
    'let expectedIdentifier = "capture-v14-\\(sourceCommitSHA.prefix(12))"',
]:
    if needle not in identity:
        raise SystemExit(f"missing current Capture build-identity contract: {needle}")

mapping = 'INFOPLIST_KEY_NembraCaptureProcedureIdentifier = "$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)";'
if project.count(mapping) != 2:
    raise SystemExit(f"expected exactly two procedure project mappings, found {project.count(mapping)}")

for needle in [
    'DEVICE_NAME = "iPhone 12"',
    'DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-12"',
    'startswith("com.apple.CoreSimulator.SimRuntime.iOS-27")',
    'PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"',
    'build_id != f"capture-v14-{source_sha[:12]}"',
    'source_sha != checkout_sha',
    'name.startswith("SIMCTL_CHILD_") or name.startswith("NEMBRA_SIMULATION_")',
    'MAX_ATTEMPTS = 40',
    'RETRY_SECONDS = 0.25',
    'guard.inspect_rendered_content(pending)',
    'retain_simctl_help("ui", ui_help)',
    'retain_simctl_help("io", io_help)',
    'app_forces_dark = "CaptureP0Root().preferredColorScheme(.dark)" in app_source',
    '"appearance", "light"',
    'light_state = "unprovisioned-system-light-requested-app-forced-dark" if app_forces_dark else "unprovisioned-light-standard"',
    'content_size", "accessibility-extra-extra-extra-large"',
    '"schemaVersion": 9',
    '"visualAcceptanceRequiresHumanReview": True',
    '"requestedSystemAppearances": ["dark", "light"]',
    '"appPreferredColorScheme": "forced-dark" if app_forces_dark else "system"',
    '"genuineLightAppearanceCoverage": not app_forces_dark',
    '"appearanceSourceSHA256": sha256(app_source_path)',
    '"screenshotRenderedContentReadinessVerified": True',
    '"simctlUIHelpSHA256": sha256(ui_help)',
    '"simctlIOHelpSHA256": sha256(io_help)',
    '"physicalAuthorityCreated": False',
    '"protocolAuthorityCreated": False',
    '"unprovisioned-dark-standard"',
    '"unprovisioned-system-light-requested-app-forced-dark"',
    '"unprovisioned-light-standard"',
    '"unprovisioned-dark-accessibility-xxxl"',
]:
    if needle not in runner:
        raise SystemExit(f"missing standalone visual truth contract: {needle}")

if 'SIMCTL_CHILD_' not in runner or '--args' in runner:
    raise SystemExit("visual runner must reject synthetic launch authority and never pass fixture launch args")
for forbidden in ["devicectl", "xctrace", "connectBLE", "writeValue", "publishDps", "local_key"]:
    if forbidden in runner:
        raise SystemExit(f"visual evidence runner contains forbidden physical/protocol surface: {forbidden}")

for needle in [
    'source-contract:',
    'runs-on: ubuntu-latest',
    'needs: source-contract',
    'runs-on: xcode-27',
    'permissions:\n  contents: read',
    'ref: ${{ github.event.pull_request.head.sha || github.sha }}',
    'persist-credentials: false',
    '/usr/bin/python3 -m py_compile scripts/ci/capture_standalone_visual_evidence.py scripts/ci/capture_visual_png_content_guard.py',
    '/usr/bin/python3 scripts/ci/tests/test_capture_visual_png_content_guard.py',
    '/usr/bin/python3 scripts/ci/tests/test_capture_standalone_visual_evidence.py',
    'CODE_SIGNING_ALLOWED=NO',
    'NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=""',
    'NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER="$procedure"',
    '/usr/bin/python3 scripts/ci/capture_standalone_visual_evidence.py',
    "assert r['schemaVersion'] == 9",
    "assert r['sourceCommitSHA'] == sys.argv[2]",
    "assert r['baselineDevice'] == 'iPhone 12' and r['baselineOS'] == 'iOS 27'",
    "assert r['requestedSystemAppearances'] == ['dark', 'light']",
    "assert r['appPreferredColorScheme'] in {'forced-dark', 'system'}",
    "assert isinstance(r['genuineLightAppearanceCoverage'], bool)",
    "assert re.fullmatch(r'[0-9a-f]{64}', r['appearanceSourceSHA256'])",
    "light_state = 'unprovisioned-system-light-requested-app-forced-dark' if r['appPreferredColorScheme'] == 'forced-dark' else 'unprovisioned-light-standard'",
    "assert r['genuineLightAppearanceCoverage'] is (r['appPreferredColorScheme'] == 'system')",
    "assert re.fullmatch(r'[0-9a-f]{64}', r['simctlUIHelpSHA256'])",
    "assert re.fullmatch(r'[0-9a-f]{64}', r['simctlIOHelpSHA256'])",
    "assert r['physicalAuthorityCreated'] is False",
    "assert r['protocolAuthorityCreated'] is False",
    'if: always()',
]:
    if needle not in workflow:
        raise SystemExit(f"missing standalone visual workflow contract: {needle}")

if workflow.count('runs-on: xcode-27') != 1:
    raise SystemExit("visual workflow must retain exactly one scarce xcode-27 Simulator job")
if workflow.count('runs-on: ubuntu-latest') != 1:
    raise SystemExit("visual workflow must retain exactly one portable source-contract job")

if re.search(r"NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=\"[0-9a-f]{64}\"", workflow):
    raise SystemExit("public visual QA must not synthesize Tuya dependency authority")

print("capture standalone visual exact-head source contract: PASS")
