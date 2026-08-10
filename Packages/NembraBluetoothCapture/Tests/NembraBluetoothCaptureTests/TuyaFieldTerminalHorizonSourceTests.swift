import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field terminal authenticated horizons")
struct TuyaFieldTerminalHorizonSourceTests {
    @Test("canonical ready is sealed before the field app publishes accepted state")
    func acceptedPreflightFreezesTheLedgerPrefix() throws {
        let appSource = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let ledgerSource = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        #expect(ledgerSource.contains("sealAcceptedObservation("))
        #expect(appSource.contains("sessionLedger.sealAcceptedObservation(for: token)"))

        guard let seal = appSource.range(of: "sessionLedger.sealAcceptedObservation(for: token)"),
              let accepted = appSource.range(of: "phase = .accepted", range: seal.upperBound..<appSource.endIndex) else {
            Issue.record("The field app must seal the canonical ready prefix before publishing accepted state.")
            return
        }

        #expect(seal.lowerBound < accepted.lowerBound)
    }

    @Test("observation-loop invalidation is terminal without being rewritten as disconnect")
    func continuityGapUsesASealedObservationFailure() throws {
        let appSource = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let ledgerSource = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        #expect(ledgerSource.contains("markObservationContinuityInvalidated("))
        #expect(ledgerSource.contains("Authenticated observation continuity was invalidated."))
        #expect(appSource.contains("sessionLedger.markObservationContinuityInvalidated(for: token)"))

        guard let watchdog = appSource.range(of: "private func startWatchdog(token:"),
              let gap = appSource.range(of: "observation_poll_gap_exceeded", range: watchdog.upperBound..<appSource.endIndex),
              let advance = appSource.range(
                of: "sessionLedger.observeCurrentConnection(for: token)",
                range: gap.upperBound..<appSource.endIndex
              ) else {
            Issue.record("The field watchdog must expose its continuity-gap terminal before any later liveness advance.")
            return
        }

        let invalidation = appSource.range(
            of: "sessionLedger.markObservationContinuityInvalidated(for: token)",
            range: watchdog.upperBound..<advance.lowerBound
        )
        #expect(invalidation != nil)
    }

    @Test("terminal horizons retire same-generation callback authority")
    func terminalHorizonAPIsRetireTheCurrentToken() throws {
        let ledgerSource = try readRepositoryFile(
            "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
        )

        guard let seal = ledgerSource.range(of: "public func sealAcceptedObservation("),
              let sealEnd = ledgerSource.range(of: "public func endConnection(", range: seal.upperBound..<ledgerSource.endIndex),
              let continuity = ledgerSource.range(of: "public func markObservationContinuityInvalidated("),
              let continuityEnd = ledgerSource.range(of: "public func", range: continuity.upperBound..<ledgerSource.endIndex) else {
            Issue.record("The ledger must expose distinct accepted and observation-invalidated terminal horizons.")
            return
        }

        let sealBody = ledgerSource[seal.lowerBound..<sealEnd.lowerBound]
        let continuityBody = ledgerSource[continuity.lowerBound..<continuityEnd.lowerBound]
        #expect(sealBody.contains("currentToken = nil"))
        #expect(continuityBody.contains("currentToken = nil"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
