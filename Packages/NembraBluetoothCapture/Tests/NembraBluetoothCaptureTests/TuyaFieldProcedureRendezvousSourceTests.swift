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

        #expect(identity.contains("static let fieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("var fieldProcedureIdentifier: String { NembraCaptureBuildIdentity.fieldProcedureIdentifier }"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
    }

    @Test("canonical runbook and field installer pin the same exact procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }

    @Test("procedure authority is mechanical rather than duplicated acceptance prose")
    func currentSourceHasMechanicalProcedureAuthority() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(identity.contains("static let fieldProcedureIdentifier = \"\(Self.procedure)\""))
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
