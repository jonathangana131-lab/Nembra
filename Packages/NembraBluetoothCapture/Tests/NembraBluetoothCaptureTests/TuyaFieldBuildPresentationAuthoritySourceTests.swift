import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture build metadata and independent field authority")
struct TuyaFieldBuildPresentationAuthoritySourceTests {
    @Test("self-described build tuple remains metadata and never becomes physical authority")
    func buildMetadataUsesBuildIdentityWithoutSelfAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let controllerAuthority = try section(
            in: app,
            from: "var privateConfig: Bool",
            to: "func consumeCorrelationAsyncInvalidation()"
        )

        #expect(controllerAuthority.contains("var fieldBuildMetadataReady: Bool { buildIdentity.hasCompleteFieldBuildMetadata }"))
        #expect(!app.contains("fieldBuildIsAuthoritative"))
        #expect(!app.contains("buildIdentity.isAuthoritativeFieldBuild"))
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool {\n        false\n    }"))
    }

    @Test("shipping preflight presents build metadata separately from one-time authorization")
    func secureLinkPresentationSeparatesMetadataFromAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let hero = try section(
            in: app,
            from: "private var hero: some View",
            to: "@ViewBuilder\n    private var stageRail"
        )
        #expect(hero.contains("test.fieldBuildMetadataReady ? \"Build metadata\" : \"Build metadata missing\""))
        #expect(hero.contains("test.fieldBuildMetadataReady ? \"checkmark.shield.fill\" : \"exclamationmark.shield\""))

        let primarySurface = try section(
            in: app,
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        #expect(primarySurface.contains("if !test.fieldBuildMetadataReady || !test.privateConfig"))
        #expect(primarySurface.contains("preflightPanel"))

        let preflight = try section(
            in: app,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        )
        #expect(preflight.contains("requirementRow(\"Capture build metadata\", ready: test.fieldBuildMetadataReady)"))
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
        #expect(authorityReady.contains("test.fieldBuildMetadataReady"))
        #expect(authorityReady.contains("&& test.fieldAuthorizationReady"))
        #expect(authorityReady.contains("&& test.privateConfig"))
        #expect(authorityReady.contains("&& test.sdkAccountLoggedIn"))
        #expect(authorityReady.contains("&& test.sdkDeviceMembershipVerified"))
        #expect(authorityReady.contains("&& test.accountIdentityLeaseIsAuthorized"))
    }

    @Test("runtime OFF1 validates metadata then consumes verifier-owned session authority")
    func runtimeGuardConsumesIndependentSessionAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try section(
            in: app,
            from: "private func beginBaselineAfterCurrentOperatorAttestation()",
            to: "private func beginCorrelationSeries"
        )

        #expect(startBaseline.contains("guard buildIdentity.hasCompleteFieldBuildMetadata else"))
        #expect(startBaseline.contains("field_build_identity_unavailable"))
        #expect(startBaseline.contains("try self.fieldAuthorization.admitOFF1Start()"))
        let metadata = try #require(startBaseline.range(of: "guard buildIdentity.hasCompleteFieldBuildMetadata else"))
        let admission = try #require(startBaseline.range(of: "try self.fieldAuthorization.admitOFF1Start()"))
        let scan = try #require(startBaseline.range(of: "self.beginCorrelationSeries()"))
        #expect(metadata.lowerBound < admission.lowerBound)
        #expect(admission.lowerBound < scan.lowerBound)
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
