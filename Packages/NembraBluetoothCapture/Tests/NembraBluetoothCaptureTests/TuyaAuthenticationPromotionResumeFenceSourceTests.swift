import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authentication-promotion resume fence")
struct TuyaAuthenticationPromotionResumeFenceSourceTests {
    @Test("auth promotion revalidates the generation after the ledger actor hop before observing UI")
    func authenticatedActorHopCannotRepaintATerminalGenerationAsObserving() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the Tuya transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<nextFunction.lowerBound])

        guard let promote = handler.range(of: "try await sessionLedger.markAuthenticated"),
              let observing = handler.range(of: "phase = .observing", range: promote.upperBound..<handler.endIndex) else {
            Issue.record("Could not isolate authenticated ledger promotion before observing UI state.")
            return
        }

        let resumeFence = String(handler[promote.upperBound..<observing.lowerBound])

        #expect(
            resumeFence.contains("currentConnectionToken == token"),
            Comment(rawValue: "The await to the session ledger can yield MainActor. A concurrent Tuya failure/source-loss callback may retire this token before the success task resumes; UI must not promote a terminal generation to observing.")
        )
        #expect(
            resumeFence.contains("phase == .authenticating"),
            Comment(rawValue: "Post-await phase must still be the same active authentication attempt before observing UI is published.")
        )
        #expect(
            resumeFence.contains("accountIdentityLeaseIsAuthorized"),
            Comment(rawValue: "Same-account exact-device source authority must be current again after the actor hop, not only before markAuthenticated was awaited.")
        )
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
