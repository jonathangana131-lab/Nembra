import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture local-BLE settlement terminal truth")
struct TuyaLocalBLESettlementTerminalSourceTests {
    @Test("local-BLE settlement timeout is authentication failure, not source-authority loss")
    func timeoutDoesNotMasqueradeAsSourceAuthorityInvalidation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let timeoutCase = app.range(of: "case .timedOut:", range: authenticated.upperBound..<app.endIndex),
              let invalidClockCase = app.range(of: "case .invalidClock:", range: timeoutCase.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the bounded local-BLE settlement timeout path.")
            return
        }

        let timeoutBody = String(app[timeoutCase.lowerBound..<invalidClockCase.lowerBound])
        #expect(timeoutBody.contains("markAuthenticationFailed"))
        #expect(!timeoutBody.contains("invalidateSourceAuthority"))
        #expect(!timeoutBody.contains("markSourceAuthorityInvalidated"))
    }

    @Test("local-BLE settlement clock failure cannot mint a source-identity terminal")
    func invalidSettlementClockFailsAuthenticationWithoutRewritingSourceAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let invalidClockCase = app.range(of: "case .invalidClock:", range: authenticated.upperBound..<app.endIndex),
              let nextFunction = app.range(of: "private func authenticationFailed", range: invalidClockCase.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the local-BLE settlement invalid-clock path.")
            return
        }

        let invalidClockBody = String(app[invalidClockCase.lowerBound..<nextFunction.lowerBound])
        #expect(invalidClockBody.contains("markAuthenticationFailed"))
        #expect(!invalidClockBody.contains("invalidateSourceAuthority"))
        #expect(!invalidClockBody.contains("markSourceAuthorityInvalidated"))
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
