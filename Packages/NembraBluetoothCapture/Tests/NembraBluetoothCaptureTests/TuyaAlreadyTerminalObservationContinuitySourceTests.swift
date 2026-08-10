import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture app already-terminal observation continuity")
struct TuyaAlreadyTerminalObservationContinuitySourceTests {
    @Test("package continuity error retires token before it throws")
    func packageContinuityErrorIsAlreadyTerminal() throws {
        let ledger = try readRepositoryFile("Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift")
        guard let functionStart = ledger.range(of: "private func requireContinuousAuthenticatedObservation(at now: UInt64) throws") else {
            Issue.record("Expected package continuity guard was not found")
            throw SourceContractError.sectionMissing
        }
        let continuity = ledger[functionStart.lowerBound...]

        guard let clear = continuity.range(of: "currentToken = nil"),
              let thrown = continuity.range(of: "throw MutationError.observationContinuityInvalidated") else {
            Issue.record("Expected terminal continuity mutation was not found")
            throw SourceContractError.sectionMissing
        }
        #expect(clear.lowerBound < thrown.lowerBound)
    }

    @Test("application receipt mirrors package terminal without terminalizing twice")
    func applicationReceiptDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let body = try catchBody(
            in: app,
            functionStart: "private func receivedApplicationUpdate",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
    }

    @Test("watchdog liveness mirrors package terminal without terminalizing twice")
    func watchdogLivenessDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let body = try catchBody(
            in: String(watchdog),
            functionStart: "sessionLedger.observeCurrentConnection(for: token)",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
    }

    @Test("acceptance seal explicitly mirrors package-terminal continuity")
    func acceptanceSealDoesNotReterminalize() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        let seal = try section(
            in: String(watchdog),
            from: "sessionLedger.sealAcceptedObservation(for: token)",
            to: "case .blocked:"
        )
        let body = try catchBody(
            in: String(seal),
            functionStart: "sessionLedger.sealAcceptedObservation(for: token)",
            errorCase: "MutationError.observationContinuityInvalidated"
        )

        #expect(body.contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(!body.contains("invalidateObservationContinuity"))
        #expect(!body.contains("markInternalLifecycleFailure"))
        #expect(String(seal).contains("accepted_prefix_seal_lifecycle_rejected"))
    }

    @Test("mirror helper mutates app ownership only")
    func mirrorHelperDoesNotInventSecondLedgerTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(
            in: app,
            from: "private func mirrorAlreadyTerminalObservationContinuity",
            to: "private func invalidateObservationContinuity"
        )

        #expect(helper.contains("currentConnectionToken == token"))
        #expect(helper.contains("watchdog?.cancel()"))
        #expect(helper.contains("currentConnectionToken = nil"))
        #expect(helper.contains("localBLESettlementToken = nil"))
        #expect(helper.contains("sdkLocalBLEOnline = false"))
        #expect(helper.contains("driver = nil"))
        #expect(helper.contains("refreshLedgerSnapshot"))
        #expect(helper.contains("phase = .failed"))
        #expect(!helper.contains("sessionLedger."))
        #expect(!helper.contains("markObservationContinuityInvalidated"))
        #expect(!helper.contains("markInternalLifecycleFailure"))
        #expect(!helper.contains("endConnection"))
    }

    private func catchBody(in source: String, functionStart: String, errorCase: String) throws -> Substring {
        guard let functionRange = source.range(of: functionStart),
              let catchRange = source.range(of: "catch TuyaAuthenticatedReadOnlySessionLedger.\(errorCase) {", range: functionRange.lowerBound..<source.endIndex),
              let nextCatch = source.range(of: "} catch", range: catchRange.upperBound..<source.endIndex) else {
            Issue.record("Expected typed catch missing: \(errorCase)")
            throw SourceContractError.sectionMissing
        }
        return source[catchRange.lowerBound..<nextCatch.lowerBound]
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
