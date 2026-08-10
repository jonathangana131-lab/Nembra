import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("compiled app identity and immutable accepted export record one exact procedure")
    func appAndAcceptedArtifactShareCanonicalProcedure() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("fieldProcedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("compiledProcedureIdentifier"))
        #expect(identity.contains("compiledProcedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(identity.contains(Self.procedure))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: buildIdentity.compiledProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\""))
        #expect(app.contains("schemaVersion: 10"))
    }

    @Test("canonical runbook and field installer pin the same exact procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        #expect(installer.contains("BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)\";"))
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
