import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pre-install source custody ordering")
struct TuyaFieldInstallerSourceCustodyOrderingSourceTests {
    @Test("independently accepted source is canonical before any retained-subject verification")
    func exactSourcePrecedesRetainedAuthorityInputs() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let sourceInput = try requiredOffset(
            containing: "NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA:?Set NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA",
            in: installer
        )
        let sourceShape = try requiredOffset(
            containing: "NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA\" =~ ^[0-9a-f]{40}$",
            in: installer
        )
        let sourceAssignment = try requiredOffset(
            containing: "SOURCE_SHA=\"$NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA\"",
            in: installer
        )
        let gitCapture = try requiredOffset(
            containing: "capture_accepted_git_source_base64()",
            in: installer
        )
        let retainedInputs = try requiredOffset(
            containing: "NEMBRA_RETAINED_IPA_PATH:?Set NEMBRA_RETAINED_IPA_PATH",
            in: installer
        )

        #expect(sourceInput < sourceShape)
        #expect(sourceShape < sourceAssignment)
        #expect(sourceAssignment < gitCapture)
        #expect(gitCapture < retainedInputs)
        #expect(installer.contains("NEMBRA_ACCEPTED_SOURCE_COMMIT_SHA cannot be the zero SHA."))
    }

    @Test("nested repository tools are captured from immutable accepted Git object bytes")
    func nestedFieldToolsCannotReopenMutableCheckoutExecutables() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("GIT_NO_REPLACE_OBJECTS=1 GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null /usr/bin/git -C \"$ROOT\" rev-parse --verify \"$SOURCE_SHA^{commit}\""))
        #expect(installer.contains("rev-parse \"$SOURCE_SHA:$relative_path\""))
        #expect(installer.contains("cat-file blob \"$blob\""))
        #expect(installer.contains("hash-object --stdin"))
        #expect(installer.contains("Captured nested repository tool bytes do not match the accepted Git object"))
        #expect(installer.contains("CAPTURE_BOOTSTRAP_SOURCE_B64=\"$(capture_accepted_git_source_base64 \"$CAPTURE_BOOTSTRAP_PATH\")\""))
        #expect(installer.contains("TUYA_PROVENANCE_SOURCE_B64=\"$(capture_accepted_git_source_base64 \"$TUYA_PROVENANCE_PATH\")\""))
        #expect(installer.contains("PRIVATE_DEVICE_RUNNER=\"$(capture_accepted_git_source_base64 \"$PRIVATE_DEVICE_RUNNER_PATH\")\""))
        #expect(!installer.contains("\"$ROOT/Scripts/bootstrap_capture_tuya_sdk.sh\""))
    }

    @Test("cross-binding verifier modules also come from the exact accepted commit")
    func retainedCrossBindingCannotUseMutableVerifierPathnames() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("manifest_source_path = \"scripts/ci/es80_retained_install_manifest.py\""))
        #expect(installer.contains("helper_source_path = \"scripts/ci/es80_retained_install_cross_binding.py\""))
        #expect(installer.contains("immutable_git_source(manifest_source_path)"))
        #expect(installer.contains("immutable_git_source(helper_source_path)"))
        #expect(installer.contains("module.__file__ = f\"<git:{accepted_source_sha}:{path}>\""))
        #expect(installer.contains("exec(compile(text, module.__file__, \"exec\"), module.__dict__)"))
    }

    @Test("pre-install stage validates stable subjects then stops before device authority")
    func preinstallCustodyEnclosesCrossBindingAndHardStop() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let firstValidation = try requiredOffset(
            containing: "validate_retained_input \"retained accepted signed IPA\"",
            in: installer
        )
        let crossBinding = try requiredOffset(
            containing: "helper.verify_cross_binding(",
            in: installer
        )
        let boundMarker = try requiredOffset(
            containing: "PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY",
            in: installer
        )
        let hardStop = try requiredOffset(
            containing: "Installation remains blocked: the production trust root and standalone app capability lifecycle are not independently accepted.",
            in: installer
        )

        #expect(firstValidation < crossBinding)
        #expect(crossBinding < boundMarker)
        #expect(boundMarker < hardStop)
        #expect(!installer.contains("devicectl device install app"))
        #expect(!installer.contains("devicectl device process launch"))
    }

    @Test("later-stage adapters are captured but not invoked by pre-install checkpoint")
    func preinstallCannotAdvanceIntoPrivateBuildOrDeviceReader() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.components(separatedBy: "run_accepted_capture_bootstrap").count == 2)
        #expect(installer.components(separatedBy: "run_accepted_tuya_provenance").count == 2)
        #expect(installer.components(separatedBy: "run_accepted_private_device_reader").count == 2)
        #expect(installer.contains("The present pre-install checkpoint does\n# not invoke them"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.tokenMissing
        }
        return range.lowerBound
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

    private enum SourceContractError: Error {
        case tokenMissing
    }
}
