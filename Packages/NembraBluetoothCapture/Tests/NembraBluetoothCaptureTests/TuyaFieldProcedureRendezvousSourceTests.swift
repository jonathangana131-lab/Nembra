import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("compiled app identity and immutable accepted export record one exact procedure")
    func appAndAcceptedArtifactShareCanonicalProcedure() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("procedureIdentifierInfoKey"))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier"))
        #expect(identity.contains("fieldProcedureIdentifier"))
        #expect(identity.contains(Self.procedure))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\""))
        #expect(app.contains("schemaVersion: 10"))
    }

    @Test("canonical runbook and field installer pin the same exact procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        #expect(installer.contains("BUILT_PROCEDURE_ID\" == \"$PROCEDURE_ID"))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }

    @Test("procedure identity cannot be satisfied by stale acceptance prose alone")
    func currentSourceHasMechanicalProcedureAuthority() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        for source in [identity, app, runbook, installer] {
            #expect(source.contains(Self.procedure))
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
