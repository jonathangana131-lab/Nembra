import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated observation app presentation")
struct TuyaAuthenticatedReadOnlyHorizonAppIntegrationTests {
    @Test("observation checklist exposes the full canonical application-evidence contract")
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

        // Repeated callbacks alone are insufficient: both may arrive before the historical
        // unauthenticated rejection boundary. The visible checklist must therefore expose the
        // package-owned post-authentication application-survival condition separately, or derive
        // visible readiness directly from the canonical package verdict.
        let exposesApplicationSurvival =
            panel.contains("TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds")
            && panel.contains("latestApplicationPayloadUptimeNanoseconds")
            && panel.contains("authenticatedAtUptimeNanoseconds")
        let usesCanonicalSurvivalPresentation = panel.contains("applicationEvidenceSurvivedHistoricalWindow")
        let derivesCanonicalVerdict = panel.contains("TuyaAuthenticatedReadOnlyPreflight.verdict")
        #expect(exposesApplicationSurvival || usesCanonicalSurvivalPresentation || derivesCanonicalVerdict)
    }

    @Test("app delegates historical-window truth to the strict package presentation helper")
    func appUsesCanonicalStrictHistoricalWindowPresentation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "var applicationEvidenceSurvivedHistoricalWindow: Bool",
            to: "var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict"
        ))

        #expect(helper.contains(
            "TuyaAuthenticatedReadOnlyPresentation.applicationEvidenceSurvivedHistoricalWindow(ledgerSnapshot)"
        ))
        #expect(!helper.contains(
            ">= TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds"
        ))
    }

    @Test("authentication-success copy describes repeated late evidence and 45-second stability")
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
        #expect(authenticatedFlow.contains("repeated same-generation scooter data"))
        #expect(authenticatedFlow.contains("startup rejection window"))
        #expect(authenticatedFlow.contains("45-second"))
    }

    @Test("canonical executable thresholds remain the app presentation source of truth")
    func canonicalThresholdsStayPinned() {
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount == 2)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds == 30_000_000_000)
        #expect(TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedConnectionNanoseconds == 45_000_000_000)
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
