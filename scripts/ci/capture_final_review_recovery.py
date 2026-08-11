#!/usr/bin/env python3
from pathlib import Path
import subprocess

WORKFLOW = Path('.github/workflows/capture-field-build-provenance.yml')
BRIDGE = Path('NembraApp/Features/Research/TuyaAccountBridge.swift')
PRODUCT_TEST = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift')
PROVENANCE_TEST = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldDependencyProvenanceSourceTests.swift')
BOOTSTRAP_WORKFLOW = Path('.github/workflows/_capture_final_review_recovery_once.yml')
HELPER = Path('scripts/ci/capture_final_review_recovery.py')


def require_once(source: str, old: str, label: str) -> None:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 match, found {count}')


# Provenance must rerun whenever any compiled standalone Capture input/dependency changes.
lines = WORKFLOW.read_text().splitlines()
anchor = '      - NembraApp/App/NembraCaptureEntrypoint.swift'
if lines.count(anchor) != 1:
    raise SystemExit(f'workflow anchor count={lines.count(anchor)}')
additions = [
    '      - NembraApp/Features/Research/TuyaAccountBridge.swift',
    '      - NembraApp/Features/Research/ES80CaptureShellView.swift',
    '      - NembraCapture-Info.plist',
    '      - Packages/NembraBluetoothCapture/**',
    '      - Podfile',
    '      - Podfile.lock',
]
for item in additions:
    if item in lines:
        raise SystemExit(f'provenance path already present unexpectedly: {item}')
idx = lines.index(anchor) + 1
lines[idx:idx] = additions
WORKFLOW.write_text('\n'.join(lines) + '\n')

# /status is status evidence, not a local-strategy resource. Do not retain a false label.
b = BRIDGE.read_text()
replacements = [
    (
        "and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// specifications, and local DP strategy before the next Bluetooth experiment.",
        "and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// and specifications before the next Bluetooth experiment.",
    ),
    ('    @Published private(set) var selectedDeviceLocalStrategy: [String: Any]?\n', ''),
    ('            "localStrategy": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:]),\n', ''),
    ('        selectedDeviceLocalStrategy = nil\n', ''),
    (
        '        async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")\n\n        let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)',
        '        let (detail, specs) = try await (detailResponse, specResponse)',
    ),
    (
        '''        selectedDeviceLocalStrategy = Self.redactAccountUID(
            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
''',
        '',
    ),
]
for old, new in replacements:
    require_once(b, old, old[:60])
    b = b.replace(old, new, 1)
for forbidden in ('selectedDeviceLocalStrategy', '"localStrategy"', '/status")'):
    if forbidden in b:
        raise SystemExit(f'false local-strategy/status label survived: {forbidden}')
for required in (
    '"status": Self.redactSecrets(selectedDeviceStatus ?? [:])',
    '"specifications": Self.redactSecrets(selectedDeviceSpecifications ?? [:])',
):
    if required not in b:
        raise SystemExit(f'required metadata export missing: {required}')
BRIDGE.write_text(b)

p = PRODUCT_TEST.read_text()
marker = '    @Test("legacy card-based Capture root is retired from the metadata bridge")\n'
require_once(p, marker, 'product-test insertion marker')
inserted = '''    @Test("cloud status is never mislabeled as local strategy evidence")
    func metadataExportPreservesStatusTruth() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\\\"localStrategy\\\""))
        #expect(!bridge.contains("/status\\\")"))
        #expect(bridge.contains("\\\"status\\\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(bridge.contains("\\\"specifications\\\": Self.redactSecrets(selectedDeviceSpecifications ?? [:])"))
    }

'''
PRODUCT_TEST.write_text(p.replace(marker, inserted + marker, 1))

d = PROVENANCE_TEST.read_text()
marker = '    @Test("dependency provenance never promotes private SDK credentials into evidence")\n'
require_once(d, marker, 'provenance-test insertion marker')
inserted = '''    @Test("field provenance reruns for all standalone Capture sources and dependency inputs")
    func workflowCoversCompiledFieldInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        let requiredPaths = [
            "NembraApp/App/NembraCaptureBuildIdentity.swift",
            "NembraApp/App/NembraCaptureEntrypoint.swift",
            "NembraApp/Features/Research/TuyaAccountBridge.swift",
            "NembraApp/Features/Research/ES80CaptureShellView.swift",
            "NembraCapture.xcodeproj/project.pbxproj",
            "NembraCapture-Info.plist",
            "Packages/NembraBluetoothCapture/**",
            "Podfile",
            "Podfile.lock"
        ]
        for path in requiredPaths {
            #expect(workflow.contains("- \\(path)"))
        }
    }

'''
PROVENANCE_TEST.write_text(d.replace(marker, inserted + marker, 1))

subprocess.run(['git', 'diff', '--check'], check=True)
changed = subprocess.check_output(['git', 'diff', '--name-only'], text=True).splitlines()
expected = sorted(map(str, (WORKFLOW, BRIDGE, PRODUCT_TEST, PROVENANCE_TEST)))
if sorted(changed) != expected:
    raise SystemExit(f'unexpected patch paths before cleanup: {changed}')

for path in (BOOTSTRAP_WORKFLOW, HELPER):
    if path.exists():
        path.unlink()

subprocess.run(['git', 'config', 'user.name', 'Nembra Capture Closure'], check=True)
subprocess.run(['git', 'config', 'user.email', 'actions@users.noreply.github.com'], check=True)
subprocess.run(['git', 'add', '-A'], check=True)
subprocess.run(['git', 'commit', '-m', 'fix(capture): close final provenance and metadata review gaps'], check=True)
subprocess.run(['git', 'push', 'origin', 'HEAD:recovery/v14-capture-final-review-fixes-sol'], check=True)
