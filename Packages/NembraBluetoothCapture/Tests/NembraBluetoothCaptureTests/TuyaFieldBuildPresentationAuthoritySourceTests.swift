import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field-build presentation authority")
struct TuyaFieldBuildPresentationAuthoritySourceTests {
    @Test("field-build authority is derived from compiled build provenance")
    func fieldBuildAuthorityUsesBuildIdentity() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controllerAuthority = try section(
            in: app,
            from: "var privateConfig: Bool",
            to: "func consumeCorrelationAsyncInvalidation()"
        )

        #expect(controllerAuthority.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(!controllerAuthority.contains("fieldBuildIsAuthoritative: Bool { accountIdentityLeaseIsAuthorized"))
        #expect(!controllerAuthority.contains("fieldBuildIsAuthoritative: Bool { sdkDeviceMembershipVerified"))
    }

    @Test("shipping preflight exposes build provenance separately and blocks OFF1 until it is authoritative")
    func secureLinkPresentationConsumesBuildAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let hero = try section(
            in: app,
            from: "private var hero: some View",
            to: "@ViewBuilder\n    private var stageRail"
        )
        #expect(hero.contains("test.fieldBuildIsAuthoritative ? \"Field build\" : \"Build blocked\""))
        #expect(hero.contains("test.fieldBuildIsAuthoritative ? \"checkmark.shield.fill\" : \"exclamationmark.shield\""))

        let primarySurface = try section(
            in: app,
            from: "private var primarySurface: some View",
            to: "private var preflightPanel: some View"
        )
        #expect(primarySurface.contains("if !test.fieldBuildIsAuthoritative || !test.privateConfig"))
        #expect(primarySurface.contains("preflightPanel"))

        let preflight = try section(
            in: app,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal"
        )
        #expect(preflight.contains("requirementRow(\"Capture build\", ready: test.fieldBuildIsAuthoritative)"))
        #expect(preflight.contains("if authorityReady"))
        #expect(preflight.contains("test.startBaseline()"))
        #expect(preflight.contains("Label(\"Start with scooter OFF\", systemImage: \"power\")"))

        let authorityReady = try section(
            in: app,
            from: "private var authorityReady: Bool",
            to: "private var currentStageIndex: Int"
        )
        #expect(authorityReady.contains("test.fieldBuildIsAuthoritative"))
        #expect(authorityReady.contains("&& test.privateConfig"))
        #expect(authorityReady.contains("&& test.sdkAccountLoggedIn"))
        #expect(authorityReady.contains("&& test.sdkDeviceMembershipVerified"))
        #expect(authorityReady.contains("&& test.accountIdentityLeaseIsAuthorized"))
        #expect(!authorityReady.contains("|| test.fieldBuildIsAuthoritative"))
    }

    @Test("runtime OFF1 admission independently rechecks exact field-build provenance")
    func runtimeGuardIsPreserved() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = try section(
            in: app,
            from: "func startBaseline()",
            to: "private func beginCorrelationSeries"
        )

        #expect(startBaseline.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        #expect(startBaseline.contains("field_build_identity_unavailable"))
        #expect(startBaseline.contains("return"))
        #expect(startBaseline.contains("verifySDKMembership"))
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