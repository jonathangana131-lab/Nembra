import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture pre-install retained-candidate verification")
struct TuyaFieldInstallerSignedBundleVerificationSourceTests {
    @Test("accepted IPA and authority subjects are hash validated before cross-binding")
    func retainedCandidateSubjectsAreValidatedBeforeCrossBinding() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        let ipaValidation = try requiredOffset(
            containing: "validate_retained_input \"retained accepted signed IPA\"",
            in: installer
        )
        let manifestValidation = try requiredOffset(
            containing: "validate_retained_input \"canonical retained-install manifest\"",
            in: installer
        )
        let finalGoValidation = try requiredOffset(
            containing: "validate_retained_input \"accepted Final-GO subject\"",
            in: installer
        )
        let deviceBindingValidation = try requiredOffset(
            containing: "validate_retained_input \"intended-device pseudonymous binding\"",
            in: installer
        )
        let crossBinding = try requiredOffset(
            containing: "helper.verify_cross_binding(",
            in: installer
        )

        #expect(ipaValidation < crossBinding)
        #expect(manifestValidation < crossBinding)
        #expect(finalGoValidation < crossBinding)
        #expect(deviceBindingValidation < crossBinding)
    }

    @Test("cross-binding names the exact retained IPA final GO Tuya lock and device pseudonym")
    func crossBindingCannotDropStableAuthoritySubjects() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("accepted_retained_ipa_sha256=retained_ipa_sha.lower()"))
        #expect(installer.contains("accepted_final_go_record_sha256=final_go_sha.lower()"))
        #expect(installer.contains("accepted_tuya_lock_sha256=tuya_lock_sha.lower()"))
        #expect(installer.contains("accepted_intended_device_pseudonym_sha256=device_binding_sha.lower()"))
        #expect(installer.contains("accepted_source_commit_sha=accepted_source_sha"))
    }

    @Test("pre-install verifier cannot resign install or launch the candidate")
    func verifierIsValidationOnly() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(installer.contains("PRE-INSTALL ONLY."))
        #expect(installer.contains("PREINSTALL_RETAINED_SUBJECTS_BOUND_NOT_INSTALL_AUTHORITY"))
        #expect(!installer.contains("codesign --sign"))
        #expect(!installer.contains("devicectl device install app"))
        #expect(!installer.contains("devicectl device process launch"))
        #expect(installer.contains("No device was contacted and no app was installed."))
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

    private enum SourceContractError: Error { case tokenMissing }
}
