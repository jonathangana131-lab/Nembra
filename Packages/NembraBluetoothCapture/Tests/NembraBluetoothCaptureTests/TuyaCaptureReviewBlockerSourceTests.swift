import Foundation
import Testing

@Suite("Capture final review blockers")
struct TuyaCaptureReviewBlockerSourceTests {
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
