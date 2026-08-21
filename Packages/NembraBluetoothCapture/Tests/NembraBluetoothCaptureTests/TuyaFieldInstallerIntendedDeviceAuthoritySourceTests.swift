import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pre-install intended-device authority")
struct TuyaFieldInstallerIntendedDeviceAuthoritySourceTests {
    @Test("pre-install accepts only an independently hashed pseudonymous device binding")
    func rawDeviceIdentityCannotEnterPreinstallAuthority() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH"))
        #expect(installer.contains("NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_SHA256"))
        #expect(installer.contains("validate_retained_input \"intended-device pseudonymous binding\""))
        #expect(installer.contains("accepted_intended_device_pseudonym_sha256=device_binding_sha.lower()"))
        #expect(!installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_FILE"))
        #expect(!installer.contains("NEMBRA_INTENDED_FIELD_DEVICE_UDID_SHA256"))
        #expect(!installer.contains("devicectl list devices"))
        #expect(!installer.contains("devicectl device install app"))
        #expect(!installer.contains("devicectl device process launch"))
    }

    @Test("private intended-device reader is captured from accepted source but not invoked pre-install")
    func privateDeviceReaderIsDeferredToLaterAcceptedRung() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PRIVATE_DEVICE_RUNNER_PATH=\"scripts/ci/es80_signed_field_artifact_private_runner.py\""))
        #expect(installer.contains("PRIVATE_DEVICE_RUNNER=\"$(capture_accepted_git_source_base64 \"$PRIVATE_DEVICE_RUNNER_PATH\")\""))
        #expect(installer.contains("run_accepted_private_device_reader()"))
        #expect(installer.components(separatedBy: "run_accepted_private_device_reader").count == 2)
        #expect(installer.contains("The present pre-install checkpoint does\n# not invoke them"))
    }

    @Test("accepted source carries the hardened private intended-device reader")
    func privateDeviceReaderExistsAndFailsClosed() throws {
        let helper = try readRepositoryFile("scripts/ci/es80_signed_field_artifact_private_runner.py")

        #expect(helper.contains("def read_private_identifier(path: Path, repository_root: Path) -> str"))
        #expect(helper.contains("O_NOFOLLOW"))
        #expect(helper.contains("O_DIRECTORY"))
        #expect(helper.contains("dir_fd=parent_descriptor"))
        #expect(helper.contains("must live outside the Nembra repository"))
        #expect(helper.contains("stat.S_ISREG"))
        #expect(helper.contains("metadata.st_mode & 0o077"))
        #expect(helper.contains("metadata.st_uid != os.geteuid()"))
        #expect(helper.contains("metadata.st_nlink != 1"))
        #expect(helper.contains("_stable_file_identity(final_metadata) != _stable_file_identity(metadata)"))
        #expect(helper.contains("private intended-device ancestor failed no-follow validation"))
        #expect(helper.contains("private intended-device path resolves inside the Nembra repository"))
        #expect(helper.contains("value != value.strip()"))
        #expect(helper.contains("value in os.fspath(path)"))
    }

    @Test("field provenance exercises the hardened private reader self-test")
    func fieldProvenanceExercisesPrivateDeviceCustody() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")

        #expect(workflow.contains("- scripts/ci/es80_signed_field_artifact_private_runner.py"))
        #expect(workflow.contains("/usr/bin/python3 -m py_compile scripts/ci/es80_signed_field_artifact_private_runner.py"))
        #expect(workflow.contains("/usr/bin/python3 -I scripts/ci/es80_signed_field_artifact_private_runner.py --self-test"))
        #expect(workflow.contains("github.event.pull_request.head.repo.full_name == github.repository"))
    }

    @Test("current secure-link procedure owns the intended iPhone baseline and exact-install requirement")
    func physicalDeviceSelectionLivesInAcceptedProcedureNotPreinstallVerifier() throws {
        let procedure = try readRepositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(procedure.contains("intended iPhone 12 / iOS 27"))
        #expect(procedure.contains("install the exact accepted signed Capture build"))
        #expect(procedure.contains("exact expected scooter device ID"))
        #expect(procedure.contains("same-account UID lease"))
        #expect(procedure.contains("physical test remains NO-GO until all are accepted"))
    }

    @Test("pre-install checkpoint cannot claim raw device discovery or installation")
    func preinstallCannotPromotePseudonymIntoDeviceContact() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY"))
        #expect(installer.contains("No device was contacted and no app was installed."))
        #expect(installer.contains("Installation remains blocked: the production trust root and standalone app capability lifecycle are not independently accepted."))
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
