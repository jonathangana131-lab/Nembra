import Foundation
import Testing

@Suite("Experiment One software export authority diagnostic")
struct PassiveBluetoothExperimentOneSoftwareExportAuthorityDiagnosticTests {
    private static func exportSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneSoftwareExport.swift"),
            encoding: .utf8
        )
    }

    @Test("wire preserves producer-issued observation-series identity instead of minting one during verification")
    func sameRunObservationAuthorityMustSurviveRoundTrip() throws {
        let source = try Self.exportSource()

        #expect(source.contains("let observationSeriesIdentity: UUID"))
        #expect(source.contains("observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue"))
        #expect(source.contains("observationSeriesIdentity: window.observationSeriesIdentity"))
        #expect(!source.contains("let authority = PassiveBluetoothCandidateObservationSeriesIdentity()"))
    }

    @Test("verification requires all four preserved windows to belong to one exact producer series")
    func crossSeriesSpliceMustFailClosed() throws {
        let source = try Self.exportSource()

        #expect(source.contains("correlationObservationSeriesMismatch"))
        #expect(source.contains("windows.allSatisfy"))
        #expect(source.contains("observationSeriesIdentity"))
    }

    @Test("closed-world verifier rejects unknown nested build, window, and candidate fields")
    func nestedUnknownFieldsMustFailClosed() throws {
        let source = try Self.exportSource()

        #expect(source.contains("allowedBuild"))
        #expect(source.contains("allowedWindow"))
        #expect(source.contains("allowedCandidate"))
        #expect(source.contains("unexpectedWireField"))
        #expect(source.contains("correlationWindows"))
        #expect(source.contains("candidates"))
    }
}
