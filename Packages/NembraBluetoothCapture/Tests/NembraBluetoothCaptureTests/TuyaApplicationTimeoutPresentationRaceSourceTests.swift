import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya package-owned incomplete horizon source contract")
struct TuyaApplicationTimeoutPresentationRaceSourceTests {
    @Test("app watchdog does not own a second zero-payload timeout terminal")
    func appWatchdogDefersIncompleteHorizonToPackageLedger() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(!source.contains("markApplicationObservationTimedOut(for: token)"))
        #expect(!source.contains("authenticated_application_timeout"))
        #expect(!source.contains("Authenticated session produced no application update before the observation deadline."))

        // The watchdog still advances package-owned liveness. The ledger's canonical
        // incomplete-session horizon owns retirement for zero, one-bootstrap, and
        // early-only callback cases, so app presentation cannot create a competing terminal.
        #expect(source.contains("try await self.sessionLedger.observeCurrentConnection(for: token)"))
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot)"))
        #expect(source.contains("mirrorAlreadyTerminalObservationContinuity"))
    }

    @Test("continuity retirement does not fabricate BLE offline")
    func packageTerminalPreservesTransportTruth() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: source,
            from: "private func mirrorAlreadyTerminalObservationContinuity(",
            to: "private func invalidateObservationContinuity("
        )
        #expect(!helper.contains("sdkLocalBLEOnline = false"))
        #expect(helper.contains("driver = nil"))
        #expect(helper.contains("no disconnect") || helper.contains("does not claim BLE"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return String(source[a.lowerBound..<b.lowerBound])
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
