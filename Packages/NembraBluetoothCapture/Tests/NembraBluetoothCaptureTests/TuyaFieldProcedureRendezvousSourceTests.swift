import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("one exact stationary procedure is bound across compiled app, export, installer, runbook, and field gate")
    func exactProcedureRendezvous() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(identity.contains("static let fieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.components(separatedBy: "INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"\(Self.procedure)\";").count == 3)
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("BUILT_PROCEDURE_ID"))
        #expect(installer.contains("[[ \"$BUILT_PROCEDURE_ID\" == \"$PROCEDURE_ID\" ]]"))
        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(workflow.contains("TuyaFieldProcedureRendezvousSourceTests.swift"))
        #expect(workflow.contains("github.event.pull_request.head.sha"))
    }

    @Test("adding procedure identity advances the sanitized export schema")
    func procedureIdentityIsSchemaTen() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9,"))
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
