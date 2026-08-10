import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture transport-success authority drift")
struct TuyaTransportSuccessAuthorityDriftSourceTests {
    @Test("transport success terminally rejects source-authority drift before local-BLE settlement")
    func transportSuccessDoesNotStrandAnAuthenticatingGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the transport-success callback handler.")
            return
        }

        let body = String(app[authenticated.lowerBound..<nextFunction.lowerBound])

        guard let acquisition = body.range(of: "let acquisitionStarted") else {
            Issue.record("Transport success must still enter the bounded local-BLE settlement window.")
            return
        }

        let preSettlement = String(body[..<acquisition.lowerBound])

        #expect(preSettlement.contains("currentConnectionToken == token"))
        #expect(preSettlement.contains("accountIdentityLeaseIsAuthorized"))
        #expect(preSettlement.contains("invalidateSourceAuthority"), Comment(rawValue: "If SDK account/device authority drifts before the success callback is handled, the active generation must be terminally retired instead of silently returning from a combined guard."))
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
