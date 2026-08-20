import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture retained-IPA installer admission checkpoint")
struct TuyaFieldInstallerRetainedIPAAdmissionSourceTests {
    @Test("legacy rebuild and device actions are unreachable before the missing contract blocker")
    func missingCurrentProcedureContractFailsBeforeLegacyAuthority() throws {
        let installer = try source()
        let blocker = try #require(installer.range(of: "Installation remains blocked:"))
        let legacyBuild = try #require(installer.range(of: "if ! xcodebuild"))
        let legacyInstall = try #require(
            installer.range(of: "xcrun devicectl device install app")
        )

        #expect(blocker.lowerBound < legacyBuild.lowerBound)
        #expect(blocker.lowerBound < legacyInstall.lowerBound)
        #expect(installer.contains("No app was rebuilt or installed"))
    }

    @Test("all stable pre-install subjects require explicit path and digest inputs")
    func everyStablePreInstallSubjectHasExplicitPathAndHash() throws {
        let installer = try source()
        for prefix in [
            "NEMBRA_RETAINED_IPA",
            "NEMBRA_ACCEPTED_BUILD_SUBJECT",
            "NEMBRA_ACCEPTED_EVIDENCE_SUBJECT",
            "NEMBRA_ACCEPTED_FINAL_GO_SUBJECT",
            "NEMBRA_ACCEPTED_TUYA_LOCK_SUBJECT",
            "NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING",
        ] {
            #expect(installer.contains("\(prefix)_PATH"))
            #expect(installer.contains("\(prefix)_SHA256"))
        }
    }

    @Test("pre-install admission cannot require the future per-attempt authorization envelope")
    func futureAttemptEnvelopeIsExcludedFromPreInstallAdmission() throws {
        let installer = try source()

        #expect(!installer.contains("NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_PATH"))
        #expect(!installer.contains("NEMBRA_CURRENT_PROCEDURE_AUTHORIZATION_ENVELOPE_SHA256"))
        #expect(!installer.contains("current-procedure authorization envelope"))
    }

    @Test("retained input admission is no-follow, bounded, stable, and mode constrained")
    func retainedInputCustodyFailsClosed() throws {
        let installer = try source()

        #expect(installer.contains("O_NOFOLLOW"))
        #expect(installer.contains("os.O_DIRECTORY"))
        #expect(installer.contains("dir_fd=directory_fd"))
        #expect(installer.contains("stat.S_ISREG"))
        #expect(installer.contains("before.st_nlink != 1"))
        #expect(installer.contains("before.st_uid != os.geteuid()"))
        #expect(installer.contains("0o077 if access_policy == \"private\" else 0o022"))
        #expect(installer.contains("identity(after) != identity(before)"))
        #expect(installer.contains("hmac.compare_digest(digest.hexdigest(), expected)"))
        #expect(installer.contains("before.st_size > maximum"))
    }

    @Test("self-test and dry-run cannot inherit tracing or place private values on argv")
    func diagnosticModesRemainNonInstalling() throws {
        let installer = try source()

        #expect(installer.contains("set +x"))
        #expect(installer.contains("--self-test"))
        #expect(installer.contains("--dry-run"))
        #expect(installer.contains("private values and hashes must not be placed on argv"))
        #expect(!installer.contains("NEMBRA_FIELD_AUTHORIZATION_PRIVATE_KEY"))
        #expect(!installer.contains("PRIVATE_KEY_PATH"))
    }

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root.appendingPathComponent(
                "scripts/field/install_one_time_capture.command"
            ),
            encoding: .utf8
        )
    }
}
