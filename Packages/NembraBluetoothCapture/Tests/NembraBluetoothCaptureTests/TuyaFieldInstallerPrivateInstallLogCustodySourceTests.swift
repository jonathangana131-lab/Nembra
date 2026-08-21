import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pre-install retained-subject custody")
struct TuyaFieldInstallerPrivateInstallLogCustodySourceTests {
    @Test("retained subjects use no-follow stable-descriptor validation")
    func retainedInputsRejectPathSubstitutionAndMutation() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("O_NOFOLLOW"))
        #expect(installer.contains("stat.S_ISREG(before.st_mode)"))
        #expect(installer.contains("before.st_nlink != 1"))
        #expect(installer.contains("before.st_uid != os.geteuid()"))
        #expect(installer.contains("forbidden_mode = 0o077 if access_policy == \"private\" else 0o022"))
        #expect(installer.contains("identity(after) != identity(before)"))
        #expect(installer.contains("hmac.compare_digest(digest.hexdigest(), expected)"))
        #expect(installer.contains("Self-test accepted a symlinked retained subject."))
    }

    @Test("private retained subjects are supplied outside argv and remain private")
    func privateSubjectsCannotBeSmuggledThroughCommandArguments() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("Only --dry-run or --self-test is accepted; private values and hashes must not be placed on argv."))
        #expect(installer.contains("NEMBRA_ACCEPTED_FINAL_GO_SUBJECT_PATH"))
        #expect(installer.contains("NEMBRA_INTENDED_DEVICE_PSEUDONYMOUS_BINDING_PATH"))
        #expect(installer.contains("validate_retained_input \"accepted Final-GO subject\""))
        #expect(installer.contains("validate_retained_input \"intended-device pseudonymous binding\""))
        #expect(installer.contains("private 1048576"))
    }

    @Test("pre-install utility has no device install launch or install-log surface")
    func preinstallUtilityCannotContactDevice() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY"))
        #expect(installer.contains("No device was contacted and no app was installed."))
        #expect(!installer.contains("devicectl device install app"))
        #expect(!installer.contains("devicectl device process launch"))
        #expect(!installer.contains("nembra-authenticated-capture-install"))
        #expect(!installer.contains("INSTALL_LOG="))
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
