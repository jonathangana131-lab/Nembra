import Foundation
import Testing

@Suite("ES80 Capture Simulator preflight authority")
struct ES80CaptureSimulatorPreflightSnapshotHandoffTests {
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

    @Test("stamped Simulator build validates provenance without creating synthetic physical authority")
    func simulatorBuildIsProvenanceOnly() throws {
        let workflow = try Self.repositorySource(".github/workflows/capture-field-build-provenance.yml")
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(workflow.contains("-sdk iphonesimulator"))
        #expect(workflow.contains("CODE_SIGNING_ALLOWED=NO"))
        #expect(workflow.contains("NEMBRA_CAPTURE_BUILD_IDENTIFIER=\"$label\""))
        #expect(workflow.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA=\"$sha\""))
        #expect(workflow.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=\"$dependency_sha\""))
        #expect(workflow.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=\"$procedure\""))
        #expect(!workflow.contains("--nembra-today-research-build"))
        #expect(!workflow.contains("NEMBRA_ES80_TODAY_RESEARCH"))
        #expect(!entrypoint.contains("simulatorQASnapshot"))
        #expect(!entrypoint.contains("PassiveBluetoothExperimentOneSimulatorQAFixture"))
    }

    @Test("current standalone preflight keeps account and exact-scooter authority in the real app")
    func preflightHasNoSyntheticSnapshotState() throws {
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")
        let authority = try Self.section(
            entrypoint,
            from: "private var authorityReady: Bool",
            to: "private var currentStageIndex: Int"
        )

        #expect(entrypoint.contains("@main @MainActor\nstruct NembraCaptureApp: App"))
        #expect(entrypoint.contains("WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }"))
        #expect(authority.contains("test.fieldBuildIsAuthoritative"))
        #expect(authority.contains("&& test.privateConfig"))
        #expect(authority.contains("&& test.sdkAccountLoggedIn"))
        #expect(authority.contains("&& test.sdkDeviceMembershipVerified"))
        #expect(authority.contains("&& test.accountIdentityLeaseIsAuthorized"))
        #expect(!entrypoint.contains("#if DEBUG && targetEnvironment(simulator)"))
        #expect(!entrypoint.contains("simulatorQAEvidenceLabel"))
    }

    @Test("selected real device context flows into Secure Link and OFF1 starts only after authorityReady")
    func currentPreflightDoesNotForwardSyntheticScenario() throws {
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")
        let preflight = try Self.section(
            entrypoint,
            from: "private var preflightPanel: some View",
            to: "private var correlationDisplayedWindowOrdinal: Int"
        )

        #expect(entrypoint.contains("NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }"))
        #expect(entrypoint.contains("init(device: TuyaAccountBridge.LinkedDevice)"))
        #expect(entrypoint.contains("_test = StateObject(wrappedValue: SecureLinkController(device: device))"))
        #expect(preflight.contains("if authorityReady"))
        #expect(preflight.contains("test.startBaseline()"))
        #expect(preflight.contains("Label(\"Start with scooter OFF\", systemImage: \"power\")"))
        #expect(!preflight.contains("simulatorQASnapshot"))
        #expect(!preflight.contains("onFreshExperimentRequested"))
        #expect(!preflight.contains("disconnectedDeclarationAccepted"))
    }
}
