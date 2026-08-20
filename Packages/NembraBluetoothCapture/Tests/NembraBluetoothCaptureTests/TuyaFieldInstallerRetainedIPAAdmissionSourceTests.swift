import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture retained-IPA installer admission checkpoint")
struct TuyaFieldInstallerRetainedIPAAdmissionSourceTests {
    @Test("legacy rebuild install and device actions are deleted before final authority exists")
    func legacyAuthorityPathsAreAbsent() throws {
        let installer = try source()

        #expect(installer.contains("Installation remains blocked:"))
        #expect(installer.contains("No device was contacted and no app was installed"))
        #expect(!installer.contains("xcodebuild"))
        #expect(!installer.contains("devicectl"))
        #expect(!installer.contains("xctrace"))
        #expect(!installer.contains("codesign"))
        #expect(!installer.contains("security cms"))
    }

    @Test("all stable pre-install subjects require explicit path and digest inputs")
    func everyStablePreInstallSubjectHasExplicitPathAndHash() throws {
        let installer = try source()
        for prefix in [
            "NEMBRA_RETAINED_INSTALL_MANIFEST",
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
        #expect(installer.contains("post-install envelope can exist only after the running"))
        #expect(installer.contains("fresh process-local challenge"))
    }

    @Test("retained input admission is no-follow, bounded, stable, mode and link constrained")
    func retainedInputCustodyFailsClosed() throws {
        let installer = try source()

        #expect(installer.contains("O_NOFOLLOW"))
        #expect(installer.contains("os.O_DIRECTORY"))
        #expect(installer.contains("dir_fd=directory_fd"))
        #expect(installer.contains("stat.S_ISREG"))
        #expect(installer.contains("before.st_nlink != 1"))
        #expect(installer.contains("before.st_uid != os.geteuid()"))
        #expect(installer.contains("0o077 if access_policy == \"private\" else 0o022"))
        #expect(installer.contains("identity(after) != identity(before"))
        #expect(installer.contains("hmac.compare_digest(digest.hexdigest(), expected)"))
        #expect(installer.contains("before.st_size > maximum"))
        #expect(installer.contains("Self-test accepted a multiply linked retained subject"))
    }

    @Test("stable subjects must cross-bind before the unconditional NO-GO stop")
    func crossBindingRunsBeforeNoGo() throws {
        let installer = try source()
        let helper = try #require(
            installer.range(of: "es80_retained_install_cross_binding.py")
        )
        let verifier = try #require(installer.range(of: "helper.verify_cross_binding("))
        let accepted = try #require(
            installer.range(of: "Stable retained-install subjects cross-bound to one canonical manifest")
        )
        let blocker = try #require(installer.range(of: "Installation remains blocked:"))

        #expect(helper.lowerBound < verifier.lowerBound)
        #expect(verifier.lowerBound < accepted.lowerBound)
        #expect(accepted.lowerBound < blocker.lowerBound)
        #expect(installer.contains("accepted_install_manifest_sha256="))
        #expect(installer.contains("accepted_retained_ipa_sha256="))
        #expect(installer.contains("accepted_external_build_record_sha256="))
        #expect(installer.contains("accepted_signed_build_evidence_sha256="))
        #expect(installer.contains("accepted_final_go_record_sha256="))
        #expect(installer.contains("accepted_tuya_lock_sha256="))
        #expect(installer.contains("accepted_intended_device_pseudonym_sha256="))
    }

    @Test("nested semantic verifier bytes come from immutable Git objects, not mutable checkout paths")
    func nestedVerifierSourceCustodyIsGitBound() throws {
        let installer = try source()

        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git -C \"$ROOT\" rev-parse"))
        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git -C \"$ROOT\" cat-file blob"))
        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1 /usr/bin/git -C \"$ROOT\" hash-object"))
        #expect(installer.contains("Capture checkout has local changes"))
        #expect(installer.contains("NESTED_TOOL_ROOT=\"$(/usr/bin/mktemp -d"))
        #expect(installer.contains("capture_accepted_git_tool \\\n  \"scripts/ci/es80_retained_install_cross_binding.py\""))
        #expect(installer.contains("capture_accepted_git_tool \\\n  \"scripts/ci/es80_retained_install_manifest.py\""))
        #expect(installer.contains("helper_path = tool_root / \"es80_retained_install_cross_binding.py\""))
        #expect(!installer.contains("helper_path = root / \"scripts/ci/es80_retained_install_cross_binding.py\""))
        #expect(installer.contains("verified_manifest.get(\"sourceCommitSHA\") != source_sha"))
        #expect(installer.contains("retained manifest source commit does not match the accepted installer checkout"))
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
        #expect(!installer.contains("publicKeyX963Representation"))
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
