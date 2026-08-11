from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 occurrence, found {count}")
    return text.replace(old, new, 1)

# Provenance workflow coverage.
workflow_path = Path('.github/workflows/capture-field-build-provenance.yml')
workflow = workflow_path.read_text()
anchor = "      - NembraApp/App/NembraCaptureEntrypoint.swift\n      - NembraCapture.xcodeproj/project.pbxproj\n"
replacement = """      - NembraApp/App/NembraCaptureEntrypoint.swift
      - NembraApp/Features/Research/TuyaAccountBridge.swift
      - NembraApp/Features/Research/ES80CaptureShellView.swift
      - NembraCapture.xcodeproj/project.pbxproj
      - NembraCapture-Info.plist
      - Packages/NembraBluetoothCapture/**
      - Podfile
      - Podfile.lock
"""
workflow = replace_once(workflow, anchor, replacement, 'provenance paths')
workflow_path.write_text(workflow)

# Cloud metadata truth: /status is not a local strategy resource.
bridge_path = Path('NembraApp/Features/Research/TuyaAccountBridge.swift')
bridge = bridge_path.read_text()
for old, new, label in [
    (
        "and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// specifications, and local DP strategy before the next Bluetooth experiment.",
        "and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// and specifications before the next Bluetooth experiment.",
        'bridge summary'
    ),
    ('    @Published private(set) var selectedDeviceLocalStrategy: [String: Any]?\n', '', 'local strategy state'),
    ('            "localStrategy": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:]),\n', '', 'local strategy export'),
    ('        selectedDeviceLocalStrategy = nil\n', '', 'local strategy reset'),
    (
        '        async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")\n\n        let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)',
        '        let (detail, specs) = try await (detailResponse, specResponse)',
        'redundant status request'
    ),
    (
        '''        selectedDeviceLocalStrategy = Self.redactAccountUID(\n            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),\n            accountUID: accountUID\n        ) as? [String: Any] ?? [:]\n''',
        '',
        'local strategy assignment'
    ),
]:
    bridge = replace_once(bridge, old, new, label)
if 'selectedDeviceLocalStrategy' in bridge or '"localStrategy"' in bridge or '/status")' in bridge:
    raise SystemExit('local-strategy/status residue remains')
bridge_path.write_text(bridge)

# Product-source regression.
product_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift')
product = product_path.read_text()
marker = '    @Test("legacy card-based Capture root is retired from the metadata bridge")\n'
addition = '''    @Test("cloud status is never mislabeled as local strategy evidence")
    func metadataExportPreservesStatusTruth() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")
        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\\\"localStrategy\\\""))
        #expect(!bridge.contains("/status\\\")"))
        #expect(bridge.contains("\\\"status\\\": Self.redactSecrets(selectedDeviceStatus ?? [:])"))
        #expect(bridge.contains("\\\"specifications\\\": Self.redactSecrets(selectedDeviceSpecifications ?? [:])"))
    }

'''
product = replace_once(product, marker, addition + marker, 'product source test marker')
product_path.write_text(product)

# Provenance-trigger regression.
prov_test_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldDependencyProvenanceSourceTests.swift')
prov_test = prov_test_path.read_text()
marker = '    @Test("dependency provenance never promotes private SDK credentials into evidence")\n'
addition = '''    @Test("field provenance reruns for all standalone Capture sources and dependency inputs")
    func workflowCoversCompiledFieldInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        for path in [
            "NembraApp/App/NembraCaptureBuildIdentity.swift",
            "NembraApp/App/NembraCaptureEntrypoint.swift",
            "NembraApp/Features/Research/TuyaAccountBridge.swift",
            "NembraApp/Features/Research/ES80CaptureShellView.swift",
            "NembraCapture.xcodeproj/project.pbxproj",
            "NembraCapture-Info.plist",
            "Packages/NembraBluetoothCapture/**",
            "Podfile",
            "Podfile.lock"
        ] {
            #expect(workflow.contains("- \\(path)"))
        }
    }

'''
prov_test = replace_once(prov_test, marker, addition + marker, 'provenance source test marker')
prov_test_path.write_text(prov_test)
