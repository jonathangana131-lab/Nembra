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

        #expect(identity.contains("fieldProcedureIdentifier"))
        #expect(identity.contains(Self.procedure))
        #expect(identity.contains("procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("let procedureIdentifier: String"))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
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
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
        #expect(installer.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        let readback = try #require(installer.range(of: "BUILT_PROCEDURE_IDENTIFIER=\"$(/usr/bin/plutil"))
        let check = try #require(installer.range(of: "[[ \"$BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID\" ]]"))
        let install = try #require(installer.range(of: "Installing SDK-integrated Capture on the intended iPhone"))
        #expect(readback.lowerBound < check.lowerBound)
        #expect(check.lowerBound < install.lowerBound)
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
