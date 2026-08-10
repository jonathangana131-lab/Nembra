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

    @Test("three package-terminal continuity catches mirror instead of terminalizing twice")
    func packageTerminalCatchesOnlyMirror() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.components(separatedBy: "mirrorAlreadyTerminalObservationContinuity(").count - 1 >= 4)
        #expect(app.contains("accepted_prefix_seal_continuity_invalidated"))
        #expect(app.contains("accepted_prefix_seal_lifecycle_rejected"))

        let application = try section(in: app, from: "private func receivedApplicationUpdate", to: "private func startWatchdog")
        let watchdog = try section(in: app, from: "private func startWatchdog", to: "private func recordObservedTransportLoss")
        #expect(String(application).contains("catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated"))
        #expect(String(application).contains("mirrorAlreadyTerminalObservationContinuity"))
        #expect(String(watchdog).contains("mirrorAlreadyTerminalObservationContinuity"))
    }

    @Test("mirror helper mutates app ownership only")
    func mirrorHelperDoesNotInventSecondLedgerTerminal() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = try section(in: app, from: "private func mirrorAlreadyTerminalObservationContinuity", to: "private func invalidateObservationContinuity")
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

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
