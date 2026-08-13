import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account identity lease app-source integration")
struct TuyaAccountIdentityLeaseAppSourceIntegrationTests {
    @Test("Secure Link uses the package identity-lease public initializer label")
    func appCallSiteMatchesPackageInitializer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let gate = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaSDKAccountIdentityLeaseGate.swift")
        #expect(gate.contains("public init(\n            isLoggedIn: Bool,"))
        #expect(app.contains("isLoggedIn: sdkAccountLoggedIn"))
        #expect(!app.contains("sdkIsLoggedIn: sdkAccountLoggedIn"))
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
