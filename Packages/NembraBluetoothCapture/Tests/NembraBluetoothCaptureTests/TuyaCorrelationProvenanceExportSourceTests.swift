import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation provenance export")
struct TuyaCorrelationProvenanceExportSourceTests {
    @Test("final package-issued correlation evidence survives scanner retirement and enters schema v8 export")
    func packageResultRemainsAuditableInExport() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("struct CorrelationProvenance: Codable, Equatable"))
        #expect(source.contains("let targetCorrelationMethod: String?"))
        #expect(source.contains("let targetCorrelationWindowCount: Int?"))
        #expect(source.contains("let targetCorrelationOperatorConfirmed: Bool"))
        #expect(source.contains("let targetCorrelationProvenance: CorrelationProvenance?"))
        #expect(source.contains("private var correlationProvenance: CorrelationProvenance?"))
        #expect(source.contains("correlationProvenance = CorrelationProvenance(result: result)"))
        #expect(source.contains("targetCorrelationMethod: targetCorrelationMethod"))
        #expect(source.contains("targetCorrelationWindowCount: targetCorrelationWindowCount"))
        #expect(source.contains("targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed"))
        #expect(source.contains("targetCorrelationProvenance: correlationProvenance"))
        #expect(source.contains("schemaVersion: 8"))

        // Preserve the exact package-issued receipt boundaries and full candidate catalogs.
        #expect(source.contains("result.windows.map"))
        #expect(source.contains("receipt.startedAtUptimeNanoseconds"))
        #expect(source.contains("receipt.endedAtUptimeNanoseconds"))
        #expect(source.contains("receipt.windowSequence.rawValue"))
        #expect(source.contains("result.observationSnapshots.map"))
        #expect(source.contains("snapshot.observationSeriesIdentity.rawValue.uuidString"))
        #expect(source.contains("candidate.id.uuidString"))
        #expect(source.contains("candidate.isConnectable"))
        #expect(source.contains("result.correlation.repeatableCandidateIdentifiers"))

        // The app preserves/reports the package result; it does not mint a second assessor authority.
        #expect(!source.contains("PassiveBluetoothPowerCycleTargetCorrelation.assess("))
    }

    @Test("a new discovery attempt cannot inherit prior target-correlation provenance")
    func resetClearsPriorSeriesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let reset = source.range(of: "private func resetDiscoverySessionOnly()"),
              let next = source.range(of: "private func failLocally", range: reset.upperBound..<source.endIndex) else {
            Issue.record("Could not isolate discovery reset.")
            return
        }
        let body = String(source[reset.lowerBound..<next.lowerBound])
        #expect(body.contains("correlationProvenance = nil"))
        #expect(body.contains("targetCorrelationMethod = nil"))
        #expect(body.contains("targetCorrelationWindowCount = nil"))
        #expect(body.contains("targetCorrelationOperatorConfirmed = false"))
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
}
