import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field installer procedure authority")
struct TuyaFieldInstallerProcedureSourceTests {
    @Test("installer launch instructions match the accepted four-window correlation procedure")
    func installerUsesFourWindowCorrelationAndExplicitConfirmation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("OFF1 -> ON1 -> OFF2 -> ON2"))
        #expect(installer.contains("fresh-manager scanner to report Live"))
        #expect(installer.contains("explicitly confirm the single repeatable correlated target"))
        #expect(installer.contains("current-session evidence only"))
        #expect(installer.contains("not permanent scooter identity"))
        #expect(installer.contains("name/RSSI/FD50/Tuya-company/historical UUID hints never substitute"))
    }

    @Test("installer cannot authorize the superseded one-baseline physical shortcut")
    func installerRejectsSupersededShortcut() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(!installer.contains("run the scooter-OFF baseline, power it ON, select the authoritative target"))
    }

    @Test("installer keeps physical stop conditions and sealed-readiness truth")
    func installerFailsClosedAtPhysicalBoundary() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("field-build provenance is not proven, STOP"))
        #expect(installer.contains("at least two genuine non-empty same-generation dpsUpdate callbacks"))
        #expect(installer.contains("the latest at least 30 seconds after SDK authentication"))
        #expect(installer.contains("canonical continuity of at least 45 seconds"))
        #expect(installer.contains("a sealed accepted prefix"))
        #expect(installer.contains("No outdoor ride is authorized by this installer"))
    }

    @Test("preinstall gate consumes retained manifest and never requires the future attempt envelope")
    func retainedManifestGatePreservesAuthorizationChronology() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_RETAINED_INSTALL_MANIFEST_PATH"))
        #expect(installer.contains("NEMBRA_RETAINED_INSTALL_MANIFEST_SHA256"))
        #expect(installer.contains("scripts/ci/es80_retained_install_manifest.py"))
        #expect(installer.contains("capture_retained_contract_source_base64"))
        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1 git -C \"$ROOT\" cat-file blob"))
        #expect(installer.contains("verify_manifest_bytes"))
        #expect(installer.contains("retainedIPASHA256"))
        #expect(installer.contains("externalBuildRecordSHA256"))
        #expect(installer.contains("signedBuildEvidenceSHA256"))
        #expect(installer.contains("finalGORecordSHA256"))
        #expect(installer.contains("tuyaDependencyLockSHA256"))
        #expect(installer.contains("intendedDevicePseudonymSHA256"))
        #expect(installer.contains("sourceCommitSHA"))
        #expect(!installer.contains("NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_PATH"))
        #expect(!installer.contains("NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_SHA256"))
        #expect(installer.contains("blocked-missing-pinned-trust-and-capability-wiring"))

        guard let manifestValidation = installer.range(
            of: "Canonical retained-install manifest matched every admitted stable subject (NOT INSTALL AUTHORITY)"
        ), let hardStop = installer.range(
            of: "Installation remains blocked: production trust is unpinned"
        ), let legacyInstall = installer.range(
            of: "say \"Installing SDK-integrated Capture on the intended iPhone\""
        ) else {
            Issue.record("Retained-manifest validation, deliberate NO-GO stop, and legacy install marker must all remain explicit.")
            return
        }
        #expect(manifestValidation.lowerBound < hardStop.lowerBound)
        #expect(hardStop.lowerBound < legacyInstall.lowerBound)
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