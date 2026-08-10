import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field app authority wiring")
struct PassiveBluetoothExperimentOneAppAuthorityWiringTests {
    @Test("standalone physical field target compiles the current Secure Link entrypoint, not the legacy app")
    func fieldTargetOwnsCurrentCaptureEntrypoint() throws {
        let project = try Self.repositorySource("NembraCapture.xcodeproj/project.pbxproj")
        let entrypoint = try Self.repositorySource("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(project.contains("NembraCaptureEntrypoint.swift in Sources"))
        #expect(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        #expect(project.contains("ES80CaptureShellView.swift in Sources"))
        #expect(project.contains("NembraBluetoothCapture in Frameworks"))
        #expect(!project.contains("NembraApp.swift in Sources"))

        #expect(entrypoint.contains("struct NembraCaptureApp: App"))
        #expect(entrypoint.contains("WindowGroup { CaptureP0Root().preferredColorScheme(.dark) }"))
        #expect(entrypoint.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(entrypoint.contains("func startBaseline()"))
        #expect(entrypoint.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))

        #expect(!entrypoint.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(!entrypoint.contains("makeResearchAuthorizedES80ForCurrentApplication()"))
        #expect(!entrypoint.contains("PassiveBluetoothCaptureFieldAuthorizationVerifier"))
        #expect(!entrypoint.contains("UserDefaults"))
    }

    @Test("field-build authority comes from stamped immutable bundle provenance and fails closed")
    func buildIdentityUsesStampedBundleProvenance() throws {
        let identity = try Self.repositorySource("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(identity.contains("static var current: Self"))
        #expect(identity.contains("from(infoDictionary: Bundle.main.infoDictionary ?? [:])"))
        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(identity.contains("var isAuthoritativeFieldBuild: Bool"))
        #expect(identity.contains("sourceCommitSHA.count == 40"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("let expectedIdentifier = \"capture-v14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(identity.contains("return buildIdentifier == expectedIdentifier"))
        #expect(identity.contains("Install Capture through the repository field installer before physical evidence collection."))

        #expect(!identity.contains("UserDefaults"))
        #expect(!identity.contains("FileManager.default"))
        #expect(!identity.contains("Task.detached"))
        #expect(!identity.contains("verifiedAdmission"))
    }

    private static func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
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
