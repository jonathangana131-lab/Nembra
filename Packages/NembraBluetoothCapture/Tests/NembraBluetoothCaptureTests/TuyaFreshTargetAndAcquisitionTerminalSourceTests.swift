import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture fresh target, export provenance, and terminal truth")
struct TuyaFreshTargetAndAcquisitionTerminalSourceTests {
    @Test("historical capture UUID is descriptive while fresh four-window evidence is exported")
    func freshCorrelationOwnsTargetAuthorityAndArtifactProvenance() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(app.contains("historicalCapturePeripheral"))
        #expect(app.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(app.contains("targetCorrelation: CorrelationExport?"))
        #expect(app.contains("observationSeriesIdentity"))
        #expect(app.contains("windowSequence"))
        #expect(app.contains("isConnectable"))
        #expect(app.contains("operatorConfirmed"))
        #expect(!app.contains("accepted-prior-physical-corebluetooth-uuid"))
    }

    @Test("local settlement timeout and invalid clock remain distinct from source authority loss")
    func acquisitionTerminalReasonsStayDistinct() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let handler = try section(in: app, from: "private func authenticated(token:", to: "private func authenticationFailed")
        let timeout = try section(in: String(handler), from: "case .timedOut:", to: "case .invalidClock:")
        #expect(timeout.contains("authenticationAcquisitionFailed"))
        #expect(!timeout.contains("invalidateSourceAuthority"))
        let invalid = String(handler[handler.range(of: "case .invalidClock:")!.lowerBound...])
        #expect(invalid.contains("invalidateChronologyIntegrity"))
        #expect(!invalid.contains("invalidateSourceAuthority"))
        #expect(app.contains("sessionLedger.markChronologyIntegrityInvalidated(for: token)"))
        #expect(app.contains("session_auth_start_chronology_rejected"))
        #expect(app.contains("application_update_clock_regressed"))
        #expect(app.contains("observation_clock_regressed"))
        #expect(app.contains("session_liveness_clock_regressed"))
        #expect(app.contains("accepted_prefix_seal_clock_regressed"))
        #expect(app.contains("application_timeout_clock_regressed"))
        #expect(app.contains("localBLESettlementToken"))
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
