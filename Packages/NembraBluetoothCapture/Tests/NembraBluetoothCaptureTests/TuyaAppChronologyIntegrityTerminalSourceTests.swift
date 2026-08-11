import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app internal-lifecycle terminal")
struct TuyaAppChronologyIntegrityTerminalSourceTests {
    @Test("local-BLE invalid clock uses the dedicated internal-lifecycle terminal")
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

        #expect(invalidClock.contains("invalidateInternalLifecycle"))
        #expect(!invalidClock.contains("authenticationAcquisitionFailed"))
        #expect(!invalidClock.contains("markAuthenticationFailed"))
        #expect(!invalidClock.contains("invalidateSourceAuthority"))
        #expect(!invalidClock.contains("invalidateObservationContinuity"))
    }

    @Test("authentication start cannot leave a package generation hidden after clock regression")
    func authenticationStartRegressionRetiresMintedGeneration() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let begin = try section(
            in: app,
            from: "private func beginOfficialConnection",
            to: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )

        #expect(begin.contains("sessionLedger.beginConnection()"))
        #expect(begin.contains("sessionLedger.markAuthenticationStarted(for: token)"))
        #expect(begin.contains("MutationError.monotonicClockRegressed"))
        #expect(begin.contains("markInternalLifecycleFailure(for: token)"))
    }

    @Test("authentication promotion clock regression uses only internal lifecycle")
    func authenticationPromotionRegressionUsesNoClockTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticated = try section(
            in: app,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            to: "private func authenticationFailed"
        )
        let observedOnline = try section(
            in: String(authenticated),
            from: "case .observedOnline:",
            to: "case .keepWaiting:"
        )

        #expect(observedOnline.contains("sessionLedger.markAuthenticated(for: token"))
        #expect(observedOnline.contains("MutationError.monotonicClockRegressed"))
        #expect(observedOnline.contains("invalidateInternalLifecycle"))
        #expect(!observedOnline.contains("invalidateSourceAuthority"))
        #expect(!observedOnline.contains("authenticationAcquisitionFailed"))
        #expect(!observedOnline.contains("markAuthenticationFailed"))
        #expect(!observedOnline.contains("invalidateObservationContinuity"))
        #expect(!observedOnline.contains("endConnection"))
    }

    @Test("application receipt clock regression cannot be relabeled as an observation gap")
    func applicationReceiptRegressionUsesNoClockTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let application = try section(
            in: app,
            from: "private func receivedApplicationUpdate",
            to: "private func startWatchdog"
        )

        #expect(application.contains("sessionLedger.recordApplicationUpdate"))
        #expect(application.contains("MutationError.monotonicClockRegressed"))
        #expect(application.contains("invalidateInternalLifecycle"))
    }

    @Test("watchdog monotonic regression retires through internal lifecycle, not observation continuity")
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

        #expect(regression.contains("invalidateInternalLifecycle"))
        #expect(!regression.contains("markObservationContinuityInvalidated"))
        #expect(!regression.contains("endConnection"))
        #expect(!regression.contains("invalidateSourceAuthority"))
    }

    @Test("watchdog ledger mutations explicitly catch clock regression")
    func watchdogLedgerMutationsCannotHideClockFailure() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = String(try section(
            in: app,
            from: "private func startWatchdog",
            to: "private func recordObservedTransportLoss"
        ))

        #expect(watchdog.contains("sessionLedger.observeCurrentConnection(for: token)"))
        #expect(watchdog.contains("sessionLedger.sealAcceptedObservation(for: token)"))
        #expect(watchdog.contains("sessionLedger.markApplicationObservationTimedOut(for: token)"))
        #expect(watchdog.components(separatedBy: "MutationError.monotonicClockRegressed").count - 1 >= 3)
        #expect(watchdog.components(separatedBy: "invalidateInternalLifecycle").count - 1 >= 4)
    }

    @Test("every app terminal that samples the clock falls back to the no-clock terminal")
    func sampledTerminalFallbacksCannotLeaveLedgerAuthorityAlive() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let terminalSections = [
            try section(in: app, from: "private func authenticationAcquisitionFailed", to: "private func receivedApplicationUpdate"),
            try section(in: app, from: "private func recordObservedTransportLoss", to: "private func invalidateSourceAuthority"),
            try section(in: app, from: "private func invalidateSourceAuthority", to: "private func invalidateObservationContinuity"),
            try section(in: app, from: "private func invalidateObservationContinuity", to: "private func invalidateInternalLifecycle")
        ]

        for terminal in terminalSections {
            #expect(terminal.contains("MutationError.monotonicClockRegressed"))
            #expect(terminal.contains("markInternalLifecycleFailure(for: token)"))
        }
    }

    @Test("app owns one dedicated helper that consumes the package no-clock terminal")
    func appConsumesInternalLifecycleTerminalExactlyAtAuthorityBoundary() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(app.contains("private func invalidateInternalLifecycle"))
        #expect(app.contains("sessionLedger.markInternalLifecycleFailure(for: token)"))

        let helper = try section(
            in: app,
            from: "private func invalidateInternalLifecycle",
            to: "private func refreshLedgerSnapshot"
        )

        #expect(helper.contains("currentConnectionToken == token"))
        #expect(helper.contains("markInternalLifecycleFailure"))
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
