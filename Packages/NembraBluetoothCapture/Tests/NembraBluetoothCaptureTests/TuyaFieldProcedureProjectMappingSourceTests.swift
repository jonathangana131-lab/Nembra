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

    @Test("signed field build still stamps and reads back the canonical procedure before install")
    func fieldInstallerRetainsProcedureReadbackAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PROCEDURE_ID=\"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(installer.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        #expect(installer.contains("[[ \"$BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID\" ]]"))
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
