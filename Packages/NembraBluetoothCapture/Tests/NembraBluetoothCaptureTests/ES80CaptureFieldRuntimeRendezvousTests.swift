import Foundation
import Testing

@Suite("ES80 Capture field runtime rendezvous")
struct ES80CaptureFieldRuntimeRendezvousTests {
    private static func repositorySource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func section(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }

    @Test("current preflight exposes exact compiled provenance before OFF1")
    func authorizedPreflightShowsCompiledCaptureTuple() throws {
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")
        let identity = try Self.repositorySource("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let engineering = try Self.section(
            entrypoint,
            from: "private var engineeringDisclosure: some View",
            to: "private func requirementRow("
        )

        #expect(entrypoint.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(entrypoint.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(entrypoint.contains("var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }"))
        #expect(entrypoint.contains("var fieldBuildSourceCommitSHA: String { buildIdentity.sourceCommitSHA }"))
        #expect(entrypoint.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(engineering.contains("LabeledContent(\"Build\", value: test.fieldBuildIdentifier)"))
        #expect(engineering.contains("LabeledContent(\"Source commit\", value: test.fieldBuildSourceCommitSHA)"))
        #expect(engineering.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(entrypoint.contains("requirementRow(\"Capture build\", ready: test.fieldBuildIsAuthoritative)"))
        #expect(entrypoint.contains("Label(\"Start with scooter OFF\", systemImage: \"power\")"))
    }

    @Test("preflight consumes compiled authority and independently rechecks it before OFF1")
    func preflightCannotMintFieldAuthority() throws {
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")
        let identity = try Self.repositorySource("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let startBaseline = try Self.section(
            entrypoint,
            from: "func startBaseline()",
            to: "func startNextCorrelationWindow()"
        )

        #expect(identity.contains("static var current: Self"))
        #expect(identity.contains("from(infoDictionary: Bundle.main.infoDictionary ?? [:])"))
        #expect(identity.contains("sourceCommitSHA.count == 40"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("let expectedIdentifier = \"capture-v14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(!identity.contains("UserDefaults"))

        let buildGuard = try #require(startBaseline.range(of: "guard buildIdentity.isAuthoritativeFieldBuild else"))
        let accountGuard = try #require(startBaseline.range(of: "guard privateConfig, sdkAccountLoggedIn else"))
        #expect(buildGuard.lowerBound < accountGuard.lowerBound)
        #expect(startBaseline.contains("field_build_identity_unavailable"))
        #expect(!startBaseline.contains("permitsPhysicalProcedure = true"))
        #expect(!entrypoint.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!entrypoint.contains("PassiveBluetoothExperimentOneFieldExecutionGate.ResearchBuild("))
    }

    @Test("Simulator cannot synthesize current secure-link authority")
    func simulatorHasNoSyntheticPreflightAuthorityPath() throws {
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authority = try Self.section(
            entrypoint,
            from: "private var authorityReady: Bool",
            to: "private var currentStageIndex: Int"
        )

        #expect(authority.contains("test.fieldBuildIsAuthoritative"))
        #expect(authority.contains("&& test.privateConfig"))
        #expect(authority.contains("&& test.sdkAccountLoggedIn"))
        #expect(authority.contains("&& test.sdkDeviceMembershipVerified"))
        #expect(authority.contains("&& test.accountIdentityLeaseIsAuthorized"))
        #expect(!entrypoint.contains("simulatorQASnapshot"))
        #expect(!entrypoint.contains("PassiveBluetoothExperimentOneSimulatorQAFixture"))
        #expect(!entrypoint.contains("targetEnvironment(simulator)"))
    }
}
