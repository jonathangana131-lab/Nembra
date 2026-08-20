import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure project mapping")
struct TuyaFieldProcedureProjectMappingSourceTests {
    @Test("Debug and Release map the named procedure build setting into the generated app plist")
    func projectMapsProcedureIntoGeneratedInfoPlist() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let mapping = "INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)\";"

        #expect(project.components(separatedBy: mapping).count - 1 == 2)
    }

    @Test("retained-install handoff validates the canonical procedure from immutable manifest source")
    func retainedInstallUsesCanonicalManifestProcedureAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let manifest = try readRepositoryFile("scripts/ci/es80_retained_install_manifest.py")
        let buildIdentity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(manifest.contains("PROCEDURE_ID = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(buildIdentity.contains("requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(installer.contains("manifest_source_path = \"scripts/ci/es80_retained_install_manifest.py\""))
        #expect(installer.contains("helper_source_path = \"scripts/ci/es80_retained_install_cross_binding.py\""))
        #expect(installer.contains("immutable_git_source(manifest_source_path)"))
        #expect(installer.contains("immutable_git_source(helper_source_path)"))
        #expect(installer.contains("helper.verify_cross_binding("))
        #expect(!installer.contains("PROCEDURE_ID=\"ES80-AUTHENTICATED-STATIONARY-v1\""))
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
}
