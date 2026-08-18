import Foundation
import Testing
@testable import NembraBluetoothCapture

extension TuyaAcceptedApplicationEvidenceSealSourceTests {
    @Test("SmartLife delivery receipt is minted only while observation owns admission")
    func callbackRequiresObservationPhaseBeforeReceiptMint() throws {
        let app = try observationPhaseRead("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let connect = app.range(of: "newDriver.connect("),
              let callback = app.range(of: "onApplicationUpdate:", range: connect.lowerBound..<app.endIndex),
              let success = app.range(of: "success:", range: callback.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate SmartLife application callback closure.")
            throw ObservationPhaseAdmissionContractError.sectionMissing
        }
        let body = String(app[callback.lowerBound..<success.lowerBound])

        let nonEmpty = try #require(body.range(of: "!update.isEmpty,"))
        let tokenFence = try #require(body.range(of: "self.currentConnectionToken == token,", range: nonEmpty.upperBound..<body.endIndex))
        let phaseFence = try #require(body.range(of: "self.phase == .observing,", range: tokenFence.upperBound..<body.endIndex))
        let cutFence = try #require(body.range(of: "!self.acceptanceCutIsClosed else", range: phaseFence.upperBound..<body.endIndex))
        let receipt = try #require(body.range(of: "self.sessionLedger.captureApplicationDelivery(", range: cutFence.upperBound..<body.endIndex))

        #expect(nonEmpty.lowerBound < tokenFence.lowerBound)
        #expect(tokenFence.lowerBound < phaseFence.lowerBound)
        #expect(phaseFence.lowerBound < cutFence.lowerBound)
        #expect(cutFence.lowerBound < receipt.lowerBound)
    }

    private func observationPhaseRead(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum ObservationPhaseAdmissionContractError: Error {
        case sectionMissing
    }
}
