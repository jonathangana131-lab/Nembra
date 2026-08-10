import Foundation
import Testing

@Suite("Capture app authority wiring")
struct PassiveBluetoothExperimentOneAppAuthorityWiringTests {
    @Test("standalone Capture target owns the current authenticated stationary authority path")
    func standaloneCaptureUsesSecureLinkAuthorityInsteadOfRetiredPassiveFactory() throws {
        let project = try repositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let entrypoint = try repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        // The physical field product is the standalone Nembra Capture target, not NembraApp.swift.
        #expect(project.contains("NembraCaptureEntrypoint.swift in Sources"))
        #expect(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        #expect(project.contains("TuyaAccountBridge.swift in Sources"))
        #expect(project.contains("productName = \"Nembra Capture\""))

        #expect(entrypoint.contains("@main @MainActor\nstruct NembraCaptureApp: App"))
        #expect(entrypoint.contains("WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }"))
        #expect(entrypoint.contains("NavigationLink(\"Continue to Capture\") { SecureLinkView(device: device) }"))
        #expect(entrypoint.contains("private struct SecureLinkView: View"))
        #expect(entrypoint.contains("@StateObject private var test: SecureLinkController"))

        // Current authority is the package-owned four-window + authenticated-session machinery.
        #expect(entrypoint.contains("private var correlationSession: PassiveBluetoothPowerCycleObservationSession?"))
        #expect(entrypoint.contains("private let sessionLedger = TuyaAuthenticatedReadOnlySessionLedger()"))
        #expect(entrypoint.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
        #expect(entrypoint.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        #expect(entrypoint.contains("guard privateConfig, sdkAccountLoggedIn else"))

        // Do not resurrect the retired passive Experiment One app factory or its old charger UI state.
        #expect(!entrypoint.contains("makeResearchAuthorizedES80ForCurrentApplication()"))
        #expect(!entrypoint.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(!entrypoint.contains("selectedChargerState = nil"))
        #expect(!entrypoint.contains("disconnectedDeclarationAccepted = false"))
    }

    @Test("field build authority comes from stamped bundle provenance without executable hashing")
    func standaloneBuildIdentityUsesStampedBundleProvenance() throws {
        let entrypoint = try repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let buildIdentity = try repositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(entrypoint.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(entrypoint.contains("var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }"))
        #expect(!entrypoint.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader.currentApplication()"))

        #expect(buildIdentity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(buildIdentity.contains("from(infoDictionary: Bundle.main.infoDictionary ?? [:])"))
        #expect(buildIdentity.contains("var isAuthoritativeFieldBuild: Bool"))
        #expect(buildIdentity.contains("sourceCommitSHA.count == 40"))
        #expect(buildIdentity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(buildIdentity.contains("let expectedIdentifier = \"capture-v14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(!buildIdentity.contains("Task.detached"))
        #expect(!buildIdentity.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
    }

    private func repositoryFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
