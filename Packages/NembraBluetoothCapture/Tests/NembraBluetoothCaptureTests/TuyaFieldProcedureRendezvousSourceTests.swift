import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field procedure rendezvous")
struct TuyaFieldProcedureRendezvousSourceTests {
    private static let procedure = "ES80-AUTHENTICATED-STATIONARY-v1"

    @Test("field build authority requires the exact compiled procedure identity")
    func buildIdentityFailsClosedWithoutCanonicalProcedure() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        #expect(identity.contains("static let procedureIdentifierInfoKey = \"NembraCaptureProcedureIdentifier\""))
        #expect(identity.contains("static let fieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("procedureIdentifier == Self.fieldProcedureIdentifier"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureProcedureIdentifier = \"$(NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER)\";"))
    }

    @Test("compiled UI, immutable export, runbook, and installer share one exact procedure")
    func oneProcedureAcrossFieldAuthoritySurfaces() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(app.contains("let procedureIdentifier: String"))
        #expect(app.contains("var fieldProcedureIdentifier: String { buildIdentity.procedureIdentifier }"))
        #expect(app.contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
        #expect(app.contains("LabeledContent(\"Procedure\", value: test.fieldProcedureIdentifier)"))
        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
        #expect(installer.contains("NEMBRA_CAPTURE_PROCEDURE_IDENTIFIER=$PROCEDURE_ID"))
        #expect(installer.contains("plutil -extract NembraCaptureProcedureIdentifier"))
        #expect(installer.contains("BUILT_PROCEDURE_IDENTIFIER\" == \"$PROCEDURE_ID"))
        #expect(installer.contains("Field procedure: $PROCEDURE_ID"))
    }

    @Test("procedure identity freezes inside the accepted export")
    func procedureIsInsideCanonicalAcceptedEnvelope() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let freeze = app.range(of: "self.sealedAcceptedExport = self.makeExport("),
              let accepted = app.range(of: "self.phase = .accepted", range: freeze.lowerBound..<app.endIndex),
              let makeExport = app.range(of: "private func makeExport") else {
            Issue.record("Accepted export freeze/makeExport markers are missing.")
            return
        }
        #expect(freeze.lowerBound < accepted.lowerBound)
        #expect(app[makeExport.lowerBound...].contains("procedureIdentifier: buildIdentity.procedureIdentifier"))
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
    }

    @Test("procedure rendezvous does not weaken dependency or command truth")
    func procedureDoesNotCreateNewPhysicalAuthority() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256"))
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