import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated observation app presentation")
struct TuyaAuthenticatedReadOnlyHorizonTestsAppIntegration {
    @Test("observation checklist uses the full canonical application-evidence requirement")
    func observationChecklistUsesFullCanonicalApplicationEvidenceRequirement() throws {
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

        // Two callbacks can both arrive before the historical ~30 s rejection boundary. The
        // visible observation requirements must therefore remain incomplete until application
        // evidence itself survives that boundary, or until the panel derives readiness directly
        // from the canonical package verdict.
        #expect(panel.contains("test.applicationEvidenceSurvivedHistoricalWindow"))
        #expect(source.contains("var applicationEvidenceSurvivedHistoricalWindow: Bool"))
        #expect(source.contains("TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds"))
        #expect(source.contains("latestApplicationPayloadUptimeNanoseconds"))
        #expect(source.contains("authenticatedAtUptimeNanoseconds"))
    }

    @Test("authentication-success copy asks for repeated evidence and the stability horizon")
    func observationCopyMatchesCanonicalEvidenceShape() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authenticatedFlow = String(try section(
            in: source,
            from: "private func authenticated(token: TuyaReadOnlyConnectionToken) async",
            to: "private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async"
        ))

        #expect(!authenticatedFlow.contains(
            "Waiting for a genuine application update and the canonical 45-second horizon"
        ))
        #expect(authenticatedFlow.contains("repeated"))
        #expect(authenticatedFlow.contains("application"))
        #expect(authenticatedFlow.contains("45-second"))
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
