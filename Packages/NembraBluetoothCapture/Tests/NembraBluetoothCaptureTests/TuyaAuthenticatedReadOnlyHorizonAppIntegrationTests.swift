import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated observation app presentation")
struct TuyaAuthenticatedReadOnlyHorizonTestsAppIntegration {
    @Test("observation checklist uses the canonical repeated-evidence requirement")
    func observationChecklistUsesCanonicalRepeatedEvidenceRequirement() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let panel = String(try section(
            in: source,
            from: "private var secureObservationPanel: some View",
            to: "private var failureRecoveryContextPanel: some View"
        ))

        #expect(panel.contains(
            "test.applicationUpdateCount >= TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount"
        ))
        #expect(!panel.contains("test.applicationUpdateCount > 0"))
    }

    @Test("observation copy asks for repeated application evidence")
    func observationCopyDoesNotPromiseReadinessFromOneUpdate() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(!source.contains("Waiting for a genuine application update and the canonical 45-second horizon"))
        #expect(source.contains("repeated"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
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
