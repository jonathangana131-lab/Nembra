from pathlib import Path

def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)

workflow_path = Path('.github/workflows/capture-field-build-provenance.yml')
workflow = workflow_path.read_text()
old_paths = '''      - NembraApp/App/NembraCaptureBuildIdentity.swift
      - NembraApp/App/NembraCaptureEntrypoint.swift
      - NembraCapture.xcodeproj/project.pbxproj
      - NembraCapture.entitlements
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldDependencyProvenanceSourceTests.swift
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerIntendedDeviceAuthoritySourceTests.swift
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldInstallerPrivateInstallLogCustodySourceTests.swift
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldProcedureRendezvousSourceTests.swift
      - Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaPrivateFieldInputProvenanceSourceTests.swift
'''
new_paths = '''      - Podfile
      - Podfile.lock
      - NembraCapture-Info.plist
      - NembraCapture.xcodeproj/**
      - NembraCapture.xcworkspace/**
      - NembraCapture.entitlements
      - NembraApp/App/NembraCaptureBuildIdentity.swift
      - NembraApp/App/NembraCaptureEntrypoint.swift
      - NembraApp/Features/Research/TuyaAccountBridge.swift
      - NembraApp/Features/Research/ES80CaptureShellView.swift
      - Packages/NembraBluetoothCapture/**
      - Packages/NembraCore/**
'''
workflow = replace_once(workflow, old_paths, new_paths, 'provenance trigger inputs')
workflow_path.write_text(workflow)

bridge_path = Path('NembraApp/Features/Research/TuyaAccountBridge.swift')
bridge = bridge_path.read_text()
bridge = replace_once(
    bridge,
    "and read-only Device Sharing endpoints to collect the device's cloud metadata, current status,\n/// specifications, and local DP strategy before the next Bluetooth experiment.",
    "and read-only Device Sharing endpoints to collect the device's cloud metadata, normalized current status,\n/// specifications, and raw read-only status-endpoint evidence before the next Bluetooth experiment.",
    'bridge purpose truth',
)
bridge = replace_once(bridge, '@Published private(set) var selectedDeviceLocalStrategy: [String: Any]?', '@Published private(set) var selectedDeviceStatusEndpointResult: Any?', 'status endpoint storage')
bridge = replace_once(bridge, '            "localStrategy": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:]),', '            "statusEndpointResult": Self.redactSecrets(selectedDeviceStatusEndpointResult ?? NSNull()),', 'export status endpoint label')
bridge = replace_once(bridge, '        selectedDeviceLocalStrategy = nil', '        selectedDeviceStatusEndpointResult = nil', 'status endpoint reset')
bridge = replace_once(
    bridge,
    '        async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")\n\n        let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)',
    '        async let statusEndpointResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")\n\n        let (detail, specs, statusEndpoint) = try await (detailResponse, specResponse, statusEndpointResponse)',
    'status endpoint request naming',
)
bridge = replace_once(
    bridge,
    '''        selectedDeviceLocalStrategy = Self.redactAccountUID(
            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),
            accountUID: accountUID
        ) as? [String: Any] ?? [:]
''',
    '''        selectedDeviceStatusEndpointResult = Self.redactAccountUID(
            Self.redactSecrets(statusEndpoint["result"] ?? NSNull()),
            accountUID: accountUID
        )
''',
    'preserve status endpoint shape',
)
bridge_path.write_text(bridge)

provenance_test_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFieldDependencyProvenanceSourceTests.swift')
provenance_test = provenance_test_path.read_text()
provenance_anchor = '    private func readRepositoryFile(_ relativePath: String) throws -> String {\n'
provenance_insert = '''    @Test("provenance workflow reruns for every compiled field-build input family")
    func provenanceWorkflowTracksCompleteFieldInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        #expect(workflow.contains("      - Podfile\\n"))
        #expect(workflow.contains("      - Podfile.lock\\n"))
        #expect(workflow.contains("      - NembraCapture-Info.plist\\n"))
        #expect(workflow.contains("      - NembraCapture.xcodeproj/**\\n"))
        #expect(workflow.contains("      - NembraCapture.xcworkspace/**\\n"))
        #expect(workflow.contains("      - NembraCapture.entitlements\\n"))
        #expect(workflow.contains("      - NembraApp/App/NembraCaptureBuildIdentity.swift\\n"))
        #expect(workflow.contains("      - NembraApp/App/NembraCaptureEntrypoint.swift\\n"))
        #expect(workflow.contains("      - NembraApp/Features/Research/TuyaAccountBridge.swift\\n"))
        #expect(workflow.contains("      - NembraApp/Features/Research/ES80CaptureShellView.swift\\n"))
        #expect(workflow.contains("      - Packages/NembraBluetoothCapture/**\\n"))
        #expect(workflow.contains("      - Packages/NembraCore/**\\n"))
    }

'''
provenance_test = replace_once(provenance_test, provenance_anchor, provenance_insert + provenance_anchor, 'provenance trigger regression test')
provenance_test_path.write_text(provenance_test)

product_test_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRootProductSurfaceSourceTests.swift')
product_test = product_test_path.read_text()
product_anchor = '    @Test("metadata preparation bridge remains cloud-only and command-free")\n'
product_insert = '''    @Test("status endpoint evidence keeps its real shape and never becomes local strategy")
    func statusEndpointEvidenceIsTruthfullyLabeled() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("@Published private(set) var selectedDeviceStatusEndpointResult: Any?"))
        #expect(bridge.contains("async let statusEndpointResponse = signedGET(path: \\\"/v1.0/m/life/devices/\\\\\\(device.id)/status\\\")"))
        #expect(bridge.contains("Self.redactSecrets(statusEndpoint[\\\"result\\\"] ?? NSNull())"))
        #expect(bridge.contains("\\\"statusEndpointResult\\\": Self.redactSecrets(selectedDeviceStatusEndpointResult ?? NSNull())"))
        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\\\"localStrategy\\\""))
        #expect(!bridge.contains("strategyResponse"))
        #expect(!bridge.contains("statusEndpoint[\\\"result\\\"] as? [String: Any]"))
    }

'''
product_test = replace_once(product_test, product_anchor, product_insert + product_anchor, 'status endpoint truth regression test')
product_test_path.write_text(product_test)

Path('.github/workflows/tmp-capture-final-review-blockers-gpt56.yml').unlink()
Path('.github/scripts/tmp_capture_final_review_blockers_gpt56.py').unlink()
