import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture final field authority")
struct TuyaFieldFinalAuthoritySourceTests {
    @Test("canonical preflight verdict is the sole acceptance authority")
    func canonicalVerdictOwnsAcceptance() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: ledgerSnapshot)"))
        #expect(!source.contains("var passed: Bool"))
        #expect(!source.contains("authoritativePreflightReady"))
    }

    @Test("first canonical ready verdict is sealed before product acceptance")
    func readyPrefixIsSealedBeforeAcceptedPhase() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let seal = source.range(of: "sessionLedger.sealAcceptedObservation(for: token)"),
              let accepted = source.range(of: "phase = .accepted", range: seal.lowerBound..<source.endIndex) else {
            Issue.record("Field controller must seal the canonical ready prefix before presenting accepted.")
            return
        }
        #expect(seal.lowerBound < accepted.lowerBound)
    }

    @Test("authenticated no-application deadline uses the terminal timeout API")
    func noApplicationDeadlineIsNotRewrittenAsDisconnect() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("sessionLedger.markApplicationObservationTimedOut(for: token)"))
        #expect(source.contains("Authenticated session produced no application update"))
    }

    @Test("ledger-owned automatic continuity invalidation is synchronized back into product state")
    func automaticContinuityFailureCannotLeaveStaleAuthenticatedUI() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let errorName = "TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated"

        #expect(
            source.contains("catch \(errorName)"),
            "A queued SDK callback can be first to detect a >5 s ledger gap. The app must catch that terminal explicitly instead of routing it through a generic second mutation."
        )
        #expect(
            source.contains("handleAutomaticContinuityInvalidation(token:"),
            "The field controller needs one terminal synchronization path that refreshes the ledger snapshot after the ledger has already retired the token."
        )

        guard let handler = source.range(of: "func handleAutomaticContinuityInvalidation("),
              let handlerEnd = source.range(of: "\n    }", range: handler.upperBound..<source.endIndex) else {
            Issue.record("Missing automatic-continuity terminal synchronization helper.")
            return
        }
        let body = source[handler.lowerBound..<handlerEnd.upperBound]
        #expect(body.contains("await refreshLedgerSnapshot()"))
        #expect(body.contains("currentConnectionToken = nil"))
        #expect(body.contains("failLocally("))
        #expect(
            !body.contains("endConnection(for:"),
            "An observation gap is not proof of physical BLE disconnect and must not be rewritten as transport loss."
        )
    }

    @Test("pre-scan authority and suspension fence remain product requirements")
    func physicalGateCannotRegressWhileTerminalAPIsLand() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        guard let start = source.range(of: "func startBaseline()"),
              let scan = source.range(of: "scanForPeripherals", range: start.upperBound..<source.endIndex),
              let membership = source.range(of: "verifySDKMembership", range: start.upperBound..<scan.lowerBound) else {
            Issue.record("OFF baseline scan must be preceded by fresh SDK account/device membership authority.")
            return
        }
        #expect(start.lowerBound < membership.lowerBound)
        #expect(membership.lowerBound < scan.lowerBound)
        #expect(source.contains("maximumObservationPollGapNanoseconds"))
        #expect(source.contains("observation_continuity_gap"))
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
