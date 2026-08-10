import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account identity lease app-source integration")
struct TuyaAccountIdentityLeaseAppSourceIntegrationTests {
    @Test("Secure Link uses the package identity-lease snapshot initializer label")
    func appCallSiteMatchesPackageInitializer() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let gate = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaSDKAccountIdentityLeaseGate.swift")
        #expect(gate.contains("public init(\n            isLoggedIn: Bool,"))
        #expect(app.contains("isLoggedIn: sdkAccountLoggedIn"))
        #expect(!app.contains("sdkIsLoggedIn: sdkAccountLoggedIn"))
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
