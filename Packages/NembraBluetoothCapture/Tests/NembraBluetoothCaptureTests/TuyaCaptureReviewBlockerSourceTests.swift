import Foundation
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
            "- .github/workflows/capture-field-build-provenance.yml",
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
