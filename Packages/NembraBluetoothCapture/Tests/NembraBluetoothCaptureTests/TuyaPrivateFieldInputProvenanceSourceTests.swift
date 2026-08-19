import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private Tuya field-input provenance")
struct TuyaPrivateFieldInputProvenanceSourceTests {
    @Test("review creates opaque authority while field mode rebinds to the exact-source accepted commitment")
    func bootstrapSeparatesReviewFromFieldAdmission() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(bootstrap.contains("capture_tuya_private_input_provenance.py"))
        #expect(bootstrap.contains("run_private_input_provenance review"))
        #expect(bootstrap.contains("run_private_input_provenance verify-review"))
        #expect(bootstrap.contains("PRIVATE_REVIEW_AUTHORITY_PATH=\"CAPTURE_TUYA_PRIVATE_INPUT_REVIEW_COMMITMENT.txt\""))
        #expect(bootstrap.contains("PRIVATE_REVIEW_AUTHORITY_BLOB"))
        #expect(bootstrap.contains("rev-parse \"$EXPECTED_FIELD_SOURCE_SHA:$PRIVATE_REVIEW_AUTHORITY_PATH\""))
        #expect(bootstrap.contains("cat-file blob \"$PRIVATE_REVIEW_AUTHORITY_BLOB\""))
        #expect(bootstrap.contains("not from the mutable checkout pathname or a caller-supplied field value"))
        #expect(!bootstrap.contains("--field-private-input-commitment"))
        #expect(bootstrap.contains("ACCEPTED_PRIVATE_INPUT_COMMITMENT"))
        #expect(bootstrap.contains("PRIVATE_REVIEW_KEY"))
        #expect(bootstrap.contains("accepted-lock mode requires the pre-existing reviewed private-input provenance record"))
        #expect(bootstrap.contains("current private Tuya build inputs do not match the externally accepted review commitment. No dependency command was run."))
        #expect(bootstrap.contains("private Tuya build inputs changed across dependency installation or no longer match the accepted review commitment"))
        #expect(bootstrap.contains("Field mode will not create or replace this witness"))
        #expect(bootstrap.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(bootstrap.contains("--security-podspec \"$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec\""))
        #expect(bootstrap.contains("--security-build \"$TUYA_PRIVATE_SDK/Build\""))
        #expect(bootstrap.contains("--identity-podspec \"$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec\""))
        #expect(bootstrap.contains("--identity-sources \"$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig\""))
        #expect(bootstrap.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(bootstrap.contains("--review-key \"$PRIVATE_REVIEW_KEY\""))
        #expect(bootstrap.contains("--accepted-commitment \"$ACCEPTED_PRIVATE_INPUT_COMMITMENT\""))

        let sourceAuthority = try requiredIndex(of: "PRIVATE_REVIEW_AUTHORITY_BLOB=", in: bootstrap)
        let preverify = try requiredIndex(of: "if ! run_private_input_provenance verify-review", in: bootstrap)
        let podInstall = try requiredIndex(of: "pod install --deployment --no-repo-update", in: bootstrap)
        let secondVerify = try requiredIndex(
            of: "private Tuya build inputs changed across dependency installation or no longer match the accepted review commitment",
            in: bootstrap
        )
        #expect(sourceAuthority < preverify)
        #expect(preverify < podInstall)
        #expect(podInstall < secondVerify)

        #expect(helper.contains("SCHEMA = \"nembra-capture-tuya-dependencies-v2\""))
        #expect(helper.contains("PRIVATE_REVIEW_DOMAIN = b\"nembra-capture-private-input-review-v1\\x00\""))
        #expect(helper.contains("PRIVATE_REVIEW_KEY_BYTES = 32"))
        #expect(helper.contains("def create_private_review("))
        #expect(helper.contains("def verify_private_review("))
        #expect(helper.contains("hmac.new(key, PRIVATE_REVIEW_DOMAIN + _record_bytes(record), hashlib.sha256)"))
        #expect(helper.contains("accepted private-input commitment must be canonical lowercase SHA-256"))
        #expect(helper.contains("private Tuya build inputs do not match the externally accepted review commitment"))
        #expect(helper.contains("O_NOFOLLOW"))
    }

    @Test("installer re-verifies ignored inputs immediately around the signed build")
    func installerCannotBuildAcrossPrivateInputDrift() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let calls = installer.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "verify_private_tuya_inputs"
        }
        #expect(calls.count == 2)

        let firstCall = try requiredIndex(of: "say \"Field procedure: $PROCEDURE_ID\"\nverify_private_tuya_inputs", in: installer)
        let build = try requiredIndex(of: "xcodebuild \\", in: installer)
        let secondCall = try requiredIndex(of: "\nverify_private_tuya_inputs\n[[ \"$(git rev-parse HEAD", in: installer)
        let appReadback = try requiredIndex(of: "APP_INFO_PLIST=\"$APP/Info.plist\"", in: installer)

        #expect(firstCall < build)
        #expect(build < secondCall)
        #expect(secondCall < appReadback)
        #expect(installer.contains("--record \"$TUYA_DEPENDENCY_PROVENANCE\""))
        #expect(installer.contains("Private Tuya SDK/app-identity inputs no longer match the bootstrap fingerprint record"))
    }

    @Test("private review authority stays opaque and does not serialize secret values")
    func reviewCommitmentDoesNotBecomeCredentialExport() throws {
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        #expect(helper.contains("cryptographic fingerprints"))
        #expect(helper.contains("It never serializes AppKey/AppSecret"))
        #expect(helper.contains("random local mode-0600 HMAC key"))
        #expect(!bootstrap.contains("app_secret_sha256"))
        #expect(!bootstrap.contains("app_key_sha256"))
        #expect(bootstrap.contains("Opaque private-input review commitment"))
        #expect(bootstrap.contains("The review key and fingerprint record stay private"))
    }

    private func requiredIndex(of needle: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: needle) else {
            Issue.record("Expected source marker missing: \(needle)")
            throw SourceContractError.markerMissing
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
        case markerMissing
    }
}
