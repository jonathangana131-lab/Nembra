import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture export schema 11 provenance continuity")
struct TuyaExportSchemaV11ProvenanceContinuitySourceTests {
    @Test("schema 11 preserves correlation dependency and procedure provenance")
    func schema11KeepsExistingProvenanceSubjects() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(source.contains("schemaVersion: 11"))
        #expect(!source.contains("schemaVersion: 10"))

        // Package-issued target-correlation provenance remains in the sanitized artifact.
        #expect(source.contains("let targetCorrelationMethod: String?"))
        #expect(source.contains("let targetCorrelationWindowCount: Int?"))
        #expect(source.contains("let targetCorrelationOperatorConfirmed: Bool"))
        #expect(source.contains("let targetCorrelationProvenance: CorrelationProvenance?"))
        #expect(source.contains("targetCorrelationMethod: targetCorrelationMethod"))
        #expect(source.contains("targetCorrelationWindowCount: targetCorrelationWindowCount"))
        #expect(source.contains("targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed"))
        #expect(source.contains("targetCorrelationProvenance: correlationProvenance"))

        // The reviewed non-secret Tuya dependency lock remains bound to the export.
        #expect(source.contains("let tuyaDependencyLockSHA256: String"))
        #expect(source.contains("tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256"))
        #expect(!source.contains("let appSecret: String"))
        #expect(!source.contains("let localKey: String"))

        // Required field-procedure provenance survives the schema move without creating authority.
        #expect(source.contains("let procedureIdentifier: String"))
        #expect(source.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
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
