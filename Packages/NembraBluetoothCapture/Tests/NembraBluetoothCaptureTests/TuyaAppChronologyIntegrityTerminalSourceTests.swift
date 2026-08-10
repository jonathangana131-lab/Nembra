import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app chronology-integrity terminal")
struct TuyaAppChronologyIntegrityTerminalSourceTests {
    @Test("local-BLE invalid clock uses the dedicated chronology-integrity terminal")
    func localBLEInvalidClockDoesNotMasqueradeAsAuthenticationFailure() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = try section(
            in: app,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            to: "private func authenticationFailed"
        )

        let invalidClock = try section(
            in: String(authenticated),
            from: "case .invalidClock:",
            to: "return"
        )

        #expect(invalidClock.contains("invalidateChronologyIntegrity"))
        #expect(!invalidClock.contains("authenticationAcquisitionFailed"))
        #expect(!invalidClock.contains("markAuthenticationFailed"))
        #expect(!invalidClock.contains("invalidateSourceAuthority"))
        #expect(!invalidClock.contains("invalidateObservationContinuity"))
    }

    @Test("watchdog monotonic regression retires through chronology integrity, not observation continuity")
    func watchdogClockRegressionUsesClockIndependentTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        )
        let regression = try section(
            in: String(watchdog),
            from: "guard now >= previousPollUptime else",
            to: "return"
        )

        #expect(regression.contains("invalidateChronologyIntegrity"))
        #expect(!regression.contains("markObservationContinuityInvalidated"))
        #expect(!regression.contains("endConnection"))
        #expect(!regression.contains("invalidateSourceAuthority"))
    }

    @Test("app owns one dedicated helper that consumes the package no-clock terminal")
    func appConsumesChronologyIntegrityTerminalExactlyAtAuthorityBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private func invalidateChronologyIntegrity"))
        #expect(app.contains("sessionLedger.markChronologyIntegrityInvalidated(for: token)"))

        let helper = try section(
            in: app,
            from: "private func invalidateChronologyIntegrity",
            to: "private func refreshLedgerSnapshot"
        )

        #expect(helper.contains("currentConnectionToken == token"))
        #expect(helper.contains("markChronologyIntegrityInvalidated"))
        #expect(helper.contains("currentConnectionToken = nil"))
        #expect(helper.contains("localBLESettlementToken = nil"))
        #expect(helper.contains("sdkLocalBLEOnline = false"))
        #expect(helper.contains("driver = nil"))
        #expect(helper.contains("phase = .failed"))
        #expect(helper.contains("refreshLedgerSnapshot"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
