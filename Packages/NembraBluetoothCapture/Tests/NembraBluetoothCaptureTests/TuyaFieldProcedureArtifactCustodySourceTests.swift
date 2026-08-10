import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure artifact custody")
struct TuyaFieldProcedureArtifactCustodySourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("authoritative build reads the procedure from its own Info plist and requires the canonical value")
    func compiledArtifactOwnsProcedureIdentity() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("static let procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("let procedureIdentifier: String"))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.components(separatedBy: "INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"\(Self.procedure)\";").count == 3)
        #expect(app.contains("var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }"))
        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
    }

    @Test("installer reads back and rejects a different built app procedure before install")
    func installerVerifiesBuiltProcedure() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let readback = installer.range(of: "BUILT_PROCEDURE_ID=\"$(/usr/bin/plutil -extract NembraCaptureProcedureIdentifier")
        let compare = installer.range(of: "[[ \"$BUILT_PROCEDURE_ID\" == \"$PROCEDURE_ID\" ]]")
        let install = installer.range(of: "say \"Installing SDK-integrated Capture on the intended iPhone\"")
        #expect(readback != nil)
        #expect(compare != nil)
        #expect(install != nil)
        if let readback, let compare, let install {
            #expect(readback.lowerBound < compare.lowerBound)
            #expect(compare.lowerBound < install.lowerBound)
        }
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
