import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture auth-success source authority")
struct TuyaAuthenticationSuccessSourceDriftSourceTests {
    @Test("current authenticating generation is terminally retired when source authority drifts before SDK success")
    func sourceDriftBeforeSDKSuccessCannotStrandAuthenticatingGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex),
              let settlement = app.range(
                of: "let acquisitionStarted",
                range: authenticated.upperBound..<nextFunction.lowerBound
              ) else {
            Issue.record("Could not isolate the SDK success callback before local-BLE settlement.")
            return
        }

        let preSettlement = String(app[authenticated.lowerBound..<settlement.lowerBound])

        // A stale callback may be ignored, but a callback for the current active
        // authenticating token must not silently return merely because the Tuya
        // account/membership lease changed. That active generation must receive
        // the dedicated source-authority terminal before local-BLE settlement.
        #expect(preSettlement.contains("currentConnectionToken == token"))
        #expect(preSettlement.contains("sdkAccountLoggedIn"))
        #expect(preSettlement.contains("sdkDeviceMembershipVerified"))
        #expect(preSettlement.contains("accountIdentityLeaseIsAuthorized"))
        #expect(preSettlement.contains("invalidateSourceAuthority("))
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
