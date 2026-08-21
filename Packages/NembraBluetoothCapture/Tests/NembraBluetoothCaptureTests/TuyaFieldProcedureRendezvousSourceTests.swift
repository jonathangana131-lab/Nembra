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
        #expect(app.contains("schemaVersion: 13"))
        #expect(!app.contains("schemaVersion: 9"))
    }

    @Test("runbook build identity and immutable retained manifest pin the same required procedure")
    func fieldSurfacesShareCanonicalProcedure() throws {
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let manifest = try readRepositoryFile("scripts/ci/es80_retained_install_manifest.py")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(runbook.contains("PROCEDURE_ID: `\(Self.procedure)`"))
        #expect(identity.contains("requiredFieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(manifest.contains("PROCEDURE_ID = \"\(Self.procedure)\""))
        #expect(installer.contains("manifest_source_path = \"scripts/ci/es80_retained_install_manifest.py\""))
        #expect(installer.contains("immutable_git_source(manifest_source_path)"))
        #expect(installer.contains("helper.verify_cross_binding("))
        #expect(!installer.contains("PROCEDURE_ID=\"\(Self.procedure)\""))
    }

    @Test("procedure authority is mechanical rather than a pre-install caller override")
    func currentSourceHasMechanicalProcedureAuthority() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let runbook = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let manifest = try readRepositoryFile("scripts/ci/es80_retained_install_manifest.py")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(identity.contains("static let requiredFieldProcedureIdentifier = \"\(Self.procedure)\""))
        #expect(identity.contains("static var fieldProcedureIdentifier: String"))
        #expect(identity.contains("current.procedureIdentifier"))
        #expect(app.contains("NembraCaptureBuildIdentity.fieldProcedureIdentifier"))
        #expect(runbook.contains(Self.procedure))
        #expect(manifest.contains(Self.procedure))
        #expect(installer.contains("NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256"))
        #expect(installer.contains("accepted_install_manifest_sha256=manifest_sha.lower()"))
        #expect(installer.contains("PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY"))
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
