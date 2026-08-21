import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer and procedure authority")
struct TuyaFieldInstallerProcedureSourceTests {
    @Test("field utility remains pre-install custody only")
    func installerStopsBeforeDeviceOrPhysicalAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PRE-INSTALL ONLY."))
        #expect(installer.contains("PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY"))
        #expect(installer.contains("stable-subjects-validated-await-app-attempt-authority"))
        #expect(installer.contains("Installation remains blocked: the production trust root and standalone app capability lifecycle are not independently accepted."))
        #expect(installer.contains("The per-attempt authorization envelope must be created only after the installed app emits its fresh challenge."))
        #expect(installer.contains("No device was contacted and no app was installed."))
    }

    @Test("canonical secure-link procedure owns four-window correlation and explicit confirmation")
    func secureLinkProcedureOwnsPhysicalCorrelationInstructions() throws {
        let procedure = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(procedure.contains("OFF1 → ON1 → OFF2 → ON2"))
        #expect(procedure.contains("fresh manager scan is live"))
        #expect(procedure.contains("Confirm correlated Bluetooth target"))
        #expect(procedure.contains("current-session authority only"))
        #expect(procedure.contains("does not establish permanent scooter identity"))
        #expect(procedure.contains("historical C7D09A22 UUID"))
        #expect(procedure.contains("cannot mint target authority"))
    }

    @Test("canonical secure-link procedure keeps physical stop conditions and sealed-readiness truth")
    func secureLinkProcedureFailsClosedAtPhysicalBoundary() throws {
        let procedure = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(procedure.contains("physical test remains NO-GO until all are accepted"))
        #expect(procedure.contains("at least two genuine non-empty same-generation `ThingSmartDeviceDelegate.dpsUpdate` callbacks"))
        #expect(procedure.contains("latest application evidence occurs at least 30 seconds after SDK authentication"))
        #expect(procedure.contains("at least 45 seconds of canonical authenticated observation"))
        #expect(procedure.contains("seal the canonical ready prefix before presenting success"))
        #expect(procedure.contains("This test is indoors and stationary."))
        #expect(procedure.contains("this experiment requires no riding or scooter motion at all"))
    }

    @Test("canonical secure-link procedure cannot authorize the superseded one-baseline shortcut")
    func secureLinkProcedureRejectsSupersededShortcut() throws {
        let procedure = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(!procedure.contains("run the scooter-OFF baseline, power it ON, select the authoritative target"))
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
