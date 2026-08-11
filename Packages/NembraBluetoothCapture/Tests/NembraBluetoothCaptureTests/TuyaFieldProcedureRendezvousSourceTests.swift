import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("compiled app identity and exports distinguish required from actually built procedure")
    func appAndArtifactUseBuiltProcedureTruth() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("let procedureIdentifier: String"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("static var fieldProcedureIdentifier: String"))
        #expect(identity.contains("current.procedureIdentifier"))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
    }

    @Test("canonical runbook and field installer pin the same exact required procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
        #expect(installer.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        let readback = try #require(installer.range(of: "BUILT_PROCEDURE_IDENTIFIER=\"$(/usr/bin/plutil"))
        let check = try #require(installer.range(of: "[[ \"$BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID\" ]]"))
        let install = try #require(installer.range(of: "Installing SDK-integrated Capture on the intended iPhone"))
        #expect(readback.lowerBound < check.lowerBound)
        #expect(check.lowerBound < install.lowerBound)
    }

    @Test("procedure authority is mechanical rather than duplicated acceptance prose")
    func currentSourceHasMechanicalProcedureAuthority() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("static var fieldProcedureIdentifier: String"))
        #expect(identity.contains("current.procedureIdentifier"))
        #expect(app.contains("NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(runbook.contains(Self.procedure))
        #expect(installer.contains(Self.procedure))
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