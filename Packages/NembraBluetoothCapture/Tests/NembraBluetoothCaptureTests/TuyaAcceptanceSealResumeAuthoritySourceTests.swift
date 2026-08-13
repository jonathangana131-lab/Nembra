import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture acceptance-seal resume authority")
struct TuyaAcceptanceSealResumeAuthoritySourceTests {
    @Test("seal resume revalidates exact app generation before accepted promotion")
    func sealResumeAuthorityFence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
        guard let start = app.range(of: "private func startWatchdog"),
              let end = app.range(of: "private func recordObservedTransportLoss", range: start.upperBound..<app.endIndex) else {
            Issue.record("watchdog source section missing")
            return
        }
        let body = String(app[start.lowerBound..<end.lowerBound])
        guard let seal = body.range(of: "try await sessionLedger.sealAcceptedObservation(for: token)"),
              let token = body.range(of: "guard self.currentConnectionToken == token,", range: seal.upperBound..<body.endIndex),
              let phase = body.range(of: "self.phase == .observing else {", range: token.upperBound..<body.endIndex),
              let transport = body.range(of: "driver.isLocallyConnected(uuid: self.tuyaUUID)", range: phase.upperBound..<body.endIndex),
              let accepted = body.range(of: "self.phase = .accepted", range: transport.upperBound..<body.endIndex) else {
            Issue.record("seal -> token/phase fence -> transport -> accepted ordering missing")
            return
        }
        #expect(seal.lowerBound < token.lowerBound)
        #expect(token.lowerBound < phase.lowerBound)
        #expect(phase.lowerBound < transport.lowerBound)
        #expect(transport.lowerBound < accepted.lowerBound)

        let fence = String(body[token.lowerBound..<transport.lowerBound])
        #expect(fence.contains("self.currentConnectionToken = nil"))
        #expect(fence.contains("self.driver = nil"))
        #expect(fence.contains("self.phase = .failed"))
        #expect(fence.contains("session_authority_changed_during_acceptance_seal"))
        #expect(fence.contains("return"))
        for forbidden in ["sessionLedger.endConnection", "markAuthenticationFailed",
                          "markSourceAuthorityInvalidated", "markObservationContinuityInvalidated",
                          "markInternalLifecycleFailure"] {
            #expect(!fence.contains(forbidden))
        }
        #expect(!String(body[seal.upperBound..<transport.lowerBound]).contains("await "))
    }
}
