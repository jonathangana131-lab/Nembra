import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field build provenance source wiring")
struct CaptureFieldBuildProvenanceSourceTests {
    @Test("standalone target embeds installer build label and full Git SHA")
    func installerBuildSettingsReachGeneratedInfoPlist() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(project.contains("INFOPLIST_KEY_NembraCaptureBuildIdentifier = \"$(NEMBRA_CAPTURE_BUILD_IDENTIFIER)\";"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureBuildCommitSHA = \"$(NEMBRA_CAPTURE_BUILD_COMMIT_SHA)\";"))

        #expect(installer.contains("SOURCE_SHA=\"$(git rev-parse HEAD)\""))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_IDENTIFIER=$BUILD_LABEL"))
        #expect(installer.contains("NEMBRA_CAPTURE_BUILD_COMMIT_SHA=$SOURCE_SHA"))
    }

    @Test("identity parser uses the same canonical Info.plist keys")
    func parserMatchesProjectKeys() throws {
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(CaptureFieldBuildIdentity.buildIdentifierInfoKey == "NembraCaptureBuildIdentifier")
        #expect(CaptureFieldBuildIdentity.commitSHAInfoKey == "NembraCaptureBuildCommitSHA")
        #expect(project.contains("INFOPLIST_KEY_\(CaptureFieldBuildIdentity.buildIdentifierInfoKey)"))
        #expect(project.contains("INFOPLIST_KEY_\(CaptureFieldBuildIdentity.commitSHAInfoKey)"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
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
