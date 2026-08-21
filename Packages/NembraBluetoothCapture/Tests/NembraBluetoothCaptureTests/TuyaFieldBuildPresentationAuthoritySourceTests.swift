import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-authorization presentation authority")
struct TuyaFieldBuildPresentationAuthoritySourceTests {
    @Test("build metadata remains provenance and never becomes physical authority")
    func buildMetadataStaysNonAuthorizing() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controllerAuthority = try section(
            in: app,
            from: "var privateConfig: Bool",
            to: "func consumeCorrelationAsyncInvalidation()"
        )

        #expect(identity.contains("var hasCompleteFieldBuildMetadata: Bool"))
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
        #expect(controllerAuthority.contains("var fieldBuildMetadataComplete: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(controllerAuthority.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(controllerAuthority.contains("var fieldAuthorizationReady: Bool { fieldAuthorization.stage == .armed }"))
        #expect(controllerAuthority.contains("var fieldAuthorizationObservationAdmitted: Bool { fieldAuthorization.stage == .observationAdmitted }"))
    }

    @Test("shipping preflight separates metadata from independently signed OFF1 authority")
    func secureLinkPresentationConsumesSignedAttemptAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let hero = try section(
            in: app,
            from: "private var hero: some View",
            to: "@ViewBuilder\n    private var stageRail"
        )
        #expect(hero.contains("test.fieldAuthorizationLifecycleValid ? \"Signed attempt\" : \"Authorization required\""))
        #expect(hero.contains("test.fieldAuthorizationLifecycleValid ? \"checkmark.shield.fill\" : \"exclamationmark.shield\""))

        let primarySurface = try section(
            in: app,
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        #expect(primarySurface.contains("if !test.fieldBuildMetadataComplete || !test.privateConfig"))
        #expect(primarySurface.contains("preflightPanel"))

        let preflight = try section(
            in: app,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        )
        #expect(preflight.contains("requirementRow(\"Capture build metadata\", ready: test.fieldBuildMetadataComplete)"))
        #expect(preflight.contains("requirementRow(\"One-time field authorization\", ready: test.fieldAuthorizationReady)"))
        #expect(preflight.contains("if authorityReady"))
        #expect(preflight.contains("stationarySafetyLaunch = .begin"))
        #expect(preflight.contains("Label(\"Review safety and begin\", systemImage: \"checkmark.shield.fill\")"))
        #expect(app.contains("StationarySafetyConfirmationSheet(launch: launch)"))
        #expect(app.contains("case .begin:\n                    test.recordFreshOperatorAttestationAndBegin()"))
        #expect(app.contains("\"I confirm — begin at OFF1\""))

        let authorityReady = try section(
            in: app,
            from: "private var authorityReady: Bool",
            to: "private var currentStageIndex: Int"
        )
        #expect(authorityReady.contains("test.fieldAuthorizationReady"))
        #expect(authorityReady.contains("&& test.privateConfig"))
        #expect(authorityReady.contains("&& test.sdkAccountLoggedIn"))
        #expect(authorityReady.contains("&& test.sdkDeviceMembershipVerified"))
        #expect(authorityReady.contains("&& test.accountIdentityLeaseIsAuthorized"))
        #expect(!authorityReady.contains("test.fieldBuildIsAuthoritative"))
    }

    @Test("runtime OFF1 consumes the signed session instead of the legacy build boolean")
    func runtimeOFF1UsesSignedSession() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try section(
            in: app,
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            to: "private func beginCorrelationSeries"
        )

        #expect(!startBaseline.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(startBaseline.contains("fieldAuthorization.admitOFF1Start()"))
        let admission = try #require(startBaseline.range(of: "fieldAuthorization.admitOFF1Start()"))
        let correlation = try #require(startBaseline.range(of: "beginCorrelationSeries()"))
        #expect(admission.lowerBound < correlation.lowerBound)
    }

    @Test("authentication and official connection advance the same opaque signed attempt")
    func secureConnectionUsesSignedSessionStages() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authentication = try section(
            in: app,
            from: "func authenticate()",
            to: "private func beginOfficialConnection(candidate: Candidate)"
        )
        let connection = try section(
            in: app,
            from: "private func beginOfficialConnection(candidate: Candidate)",
            to: "private func authenticated(token: TuyaReadOnlyConnectionToken)"
        )

        #expect(!authentication.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(authentication.contains("fieldAuthorization.admitAuthenticationStart()"))
        #expect(!connection.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(connection.contains("fieldAuthorization.admitOfficialConnectionStart()"))
        let admission = try #require(connection.range(of: "fieldAuthorization.admitOfficialConnectionStart()"))
        let driver = try #require(connection.range(of: "OfficialTuyaFactory.make()"))
        #expect(admission.lowerBound < driver.lowerBound)
    }

    @Test("accepted artifact keeps metadata and signed observation authority through the seal")
    func acceptanceSealKeepsSignedObservationAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let watchdog = try section(
            in: app,
            from: "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            to: "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)"
        )

        #expect(watchdog.contains("buildIdentity.hasCompleteFieldBuildMetadata"))
        #expect(watchdog.contains("fieldAuthorizationObservationAdmitted"))
        #expect(!watchdog.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(watchdog.contains("freezeAcceptedArtifactForAuthorizationSeal()"))
        #expect(watchdog.contains("fieldAuthorization.sealAfterAcceptedArtifactFreeze()"))
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
