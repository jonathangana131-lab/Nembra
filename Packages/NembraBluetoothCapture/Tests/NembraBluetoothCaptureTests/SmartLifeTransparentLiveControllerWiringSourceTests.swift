import Foundation
import Testing

@Suite("Smart Life transparent live controller wiring source contract")
struct SmartLifeTransparentLiveControllerWiringSourceTests {
    private func source() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repo = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repo.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("controller arms receive-only delegate only after authenticated local BLE promotion")
    func authenticatedArmIsGenerationFenced() throws {
        let s = try source()
        let authentication = try #require(s.range(of: "markAuthenticated(for: token, method: .smartLifeAppSDK)"))
        let finalLocalBLE = try #require(s.range(of: "let promotionLocalBLEOnline = promotionDriver.isLocallyConnected(uuid: tuyaUUID)"))
        let arm = try #require(s.range(of: "armVerdictAfterAuthenticatedLocalBLE("))
        #expect(authentication.lowerBound < finalLocalBLE.lowerBound)
        #expect(finalLocalBLE.lowerBound < arm.lowerBound)
        #expect(s.contains("authenticatedPreflightSnapshot: ledgerSnapshot"))
        #expect(s.contains("authenticated_transparent_receive_delegate_installed"))
    }

    @Test("transport milestone stays semantics-free and prevents false application timeout")
    func physicalTransportMilestoneIsReadOnly() throws {
        let s = try source()
        #expect(s.contains("satisfiesDocumentedAuthenticatedTransportAcceptance"))
        #expect(s.contains("transparentTransportAcceptanceLoggedGeneration != token.diagnosticGeneration"))
        #expect(s.contains("raw FD50 characteristic custody and scooter DP semantics remain unassigned"))
        #expect(s.contains("documented-tuya-transport-only"))
    }

    @Test("terminal lifecycle retires exact transparent generation")
    func terminalLifecycleRetiresReceiveLease() throws {
        let s = try source()
        #expect(s.contains("transparentFieldSession.terminalLifecycleDidOccur(for: token)"))
    }
}
