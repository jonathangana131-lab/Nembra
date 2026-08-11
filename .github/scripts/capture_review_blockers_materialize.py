from pathlib import Path

workflow_path = Path('.github/workflows/capture-field-build-provenance.yml')
workflow = workflow_path.read_text()
start = workflow.index('  pull_request:\n    paths:\n')
end = workflow.index('  workflow_dispatch:\n', start)
old_paths = workflow[start:end]
required_old = [
    'NembraApp/App/NembraCaptureBuildIdentity.swift',
    'NembraApp/App/NembraCaptureEntrypoint.swift',
    'NembraCapture.xcodeproj/project.pbxproj',
    'scripts/field/install_one_time_capture.command',
]
for token in required_old:
    if token not in old_paths:
        raise SystemExit(f'provenance trigger block drifted; missing {token}')
new_paths = '''  pull_request:\n    paths:\n      - Podfile\n      - Podfile.lock\n      - NembraCapture-Info.plist\n      - NembraCapture.xcodeproj/**\n      - NembraCapture.xcworkspace/**\n      - NembraCapture.entitlements\n      - NembraApp/App/NembraCaptureBuildIdentity.swift\n      - NembraApp/App/NembraCaptureEntrypoint.swift\n      - NembraApp/Features/Research/TuyaAccountBridge.swift\n      - NembraApp/Features/Research/ES80CaptureShellView.swift\n      - Packages/NembraBluetoothCapture/**\n      - Packages/NembraCore/**\n      - Scripts/**\n      - scripts/field/**\n      - scripts/ci/**\n      - .github/workflows/capture-field-build-provenance.yml\n'''
workflow = workflow[:start] + new_paths + workflow[end:]
workflow_path.write_text(workflow)

bridge_path = Path('NembraApp/Features/Research/TuyaAccountBridge.swift')
bridge = bridge_path.read_text()
replacements = [
    (
        'and read-only Device Sharing endpoints to collect the device\'s cloud metadata, current status,\n/// specifications, and local DP strategy before the next Bluetooth experiment.',
        'and read-only Device Sharing endpoints to collect the device\'s cloud metadata, current status,\n/// specifications, and cloud status payload before the next Bluetooth experiment.',
    ),
    (
        '@Published private(set) var selectedDeviceLocalStrategy: [String: Any]?',
        '@Published private(set) var selectedDeviceCloudStatus: Any?',
    ),
    (
        '"localStrategy": Self.redactSecrets(selectedDeviceLocalStrategy ?? [:]),',
        '"cloudStatusResponse": Self.redactSecrets(selectedDeviceCloudStatus ?? []),',
    ),
    (
        'selectedDeviceLocalStrategy = nil',
        'selectedDeviceCloudStatus = nil',
    ),
    (
        'async let strategyResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")',
        'async let cloudStatusResponse = signedGET(path: "/v1.0/m/life/devices/\\(device.id)/status")',
    ),
    (
        'let (detail, specs, strategy) = try await (detailResponse, specResponse, strategyResponse)',
        'let (detail, specs, cloudStatus) = try await (detailResponse, specResponse, cloudStatusResponse)',
    ),
    (
        '''        selectedDeviceLocalStrategy = Self.redactAccountUID(\n            Self.redactSecrets(strategy["result"] as? [String: Any] ?? [:]),\n            accountUID: accountUID\n        ) as? [String: Any] ?? [:]\n''',
        '''        selectedDeviceCloudStatus = Self.redactAccountUID(\n            Self.redactSecrets(cloudStatus["result"] ?? []),\n            accountUID: accountUID\n        )\n''',
    ),
]
for old, new in replacements:
    count = bridge.count(old)
    if count != 1:
        raise SystemExit(f'expected exactly one bridge occurrence, found {count}: {old[:80]}')
    bridge = bridge.replace(old, new, 1)
bridge_path.write_text(bridge)

contract_path = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureReviewBlockerSourceTests.swift')
contract_path.write_text(r'''import Foundation
import Testing

@Suite("Capture final review blockers")
struct TuyaCaptureReviewBlockerSourceTests {
    @Test("field provenance runs for every compiled Capture and dependency input family")
    func provenanceTriggerCoversFieldBuildInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        let requiredPaths = [
            "- Podfile",
            "- Podfile.lock",
            "- NembraCapture-Info.plist",
            "- NembraCapture.xcodeproj/**",
            "- NembraCapture.xcworkspace/**",
            "- NembraCapture.entitlements",
            "- NembraApp/App/NembraCaptureBuildIdentity.swift",
            "- NembraApp/App/NembraCaptureEntrypoint.swift",
            "- NembraApp/Features/Research/TuyaAccountBridge.swift",
            "- NembraApp/Features/Research/ES80CaptureShellView.swift",
            "- Packages/NembraBluetoothCapture/**",
            "- Packages/NembraCore/**",
            "- Scripts/**",
            "- scripts/field/**",
            "- scripts/ci/**",
        ]
        for path in requiredPaths {
            #expect(workflow.contains(path), "Missing field-provenance trigger: \(path)")
        }
        #expect(workflow.contains("github.event.pull_request.head.repo.full_name == github.repository"))
    }

    @Test("Tuya status endpoint remains status evidence with its original JSON shape")
    func cloudStatusIsNotPromotedToLocalStrategy() throws {
        let bridge = try readRepositoryFile("NembraApp/Features/Research/TuyaAccountBridge.swift")

        #expect(bridge.contains("@Published private(set) var selectedDeviceCloudStatus: Any?"))
        #expect(bridge.contains("signedGET(path: \"/v1.0/m/life/devices/\\(device.id)/status\")"))
        #expect(bridge.contains("Self.redactSecrets(cloudStatus[\"result\"] ?? [])"))
        #expect(bridge.contains("\"cloudStatusResponse\": Self.redactSecrets(selectedDeviceCloudStatus ?? [])"))
        #expect(!bridge.contains("selectedDeviceLocalStrategy"))
        #expect(!bridge.contains("\"localStrategy\""))
        #expect(!bridge.contains("cloudStatus[\"result\"] as? [String: Any]"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
''')
