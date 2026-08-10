import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("compiled build identity requires the exact built procedure")
    func compiledBuildIdentityRequiresCanonicalBuiltProcedure() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(identity.contains("procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("requiredProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("let procedureIdentifier: String"))
        #expect(identity.contains("procedureIdentifier: (infoDictionary[procedureIdentifierInfoKey] as? String) ?? \"\""))
        #expect(identity.contains("procedureIdentifier == Self.requiredProcedureIdentifier"))
        #expect(identity.contains("static var fieldProcedureIdentifier: String"))
        #expect(identity.contains("current.procedureIdentifier"))
    }

    @Test("immutable accepted export and UI consume the built procedure value")
    func appAndAcceptedArtifactUseBuiltProcedure() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        #expect(identity.contains("static var fieldProcedureIdentifier: String"))
        #expect(identity.contains("current.procedureIdentifier"))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(app.contains("schemaVersion: 10"))
        #expect(app.contains("self.sealedAcceptedExport = self.makeExport("))
        #expect(app.contains("envelope = sealedAcceptedExport"))
    }

    @Test("authoritative field wrapper stamps and verifies the exact built procedure before install continues")
    func installerChainProvesBuiltProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let authoritative = try readRepositoryFile("scripts/field/install_one_time_capture_authoritative.command")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(runbook.contains("install_one_time_capture_authoritative.command"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
        #expect(authoritative.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(authoritative.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier=$NEMBRA_CAPTURE_PROCEDURE_ID"))
        #expect(authoritative.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        #expect(authoritative.contains("built_procedure\" == \"$NEMBRA_CAPTURE_PROCEDURE_ID"))
        #expect(authoritative.contains("Installation is blocked."))
        #expect(authoritative.contains("\"$BASE_INSTALLER\" \"$@\""))
    }

    @Test("procedure rendezvous does not create physical protocol authority")
    func procedureDoesNotCreateNewPhysicalAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("rawFD50BytesCaptured: false"))
        #expect(app.contains("dpQueriesSent: false"))
        #expect(app.contains("dpCommandsSent: false"))
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
