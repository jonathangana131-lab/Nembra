import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("compiled UI immutable export runbook and installer share one exact procedure")
    func oneProcedureAcrossFieldAuthoritySurfaces() throws {
        let identity = try read("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try read("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try read("scripts/field/install_one_time_capture.command")

        #expect(identity.contains("static let fieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("procedureIdentifier: NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }

    @Test("procedure-bearing accepted export advances beyond dependency-lock schema")
    func exportSchemaAdvances() throws {
        let app = try read("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
    }

    private func read(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
