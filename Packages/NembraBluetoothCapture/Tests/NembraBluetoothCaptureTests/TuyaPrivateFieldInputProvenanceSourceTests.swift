import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private Tuya field-input provenance")
struct TuyaPrivateFieldInputProvenanceSourceTests {
    @Test("bootstrap snapshots every ignored private build input")
    func bootstrapOwnsExactPrivateInputSnapshot() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(bootstrap.contains("capture_tuya_private_input_provenance.py"))
        #expect(bootstrap.contains("\"$PROVENANCE_HELPER\" snapshot"))
        #expect(bootstrap.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(bootstrap.contains("--security-podspec \"$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec\""))
        #expect(bootstrap.contains("--security-build \"$TUYA_PRIVATE_SDK/Build\""))
        #expect(bootstrap.contains("--identity-podspec \"$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec\""))
        #expect(bootstrap.contains("--identity-sources \"$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig\""))
        #expect(bootstrap.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(bootstrap.contains("private Tuya dependency provenance record is not mode 0600"))

        #expect(helper.contains("SCHEMA = \"nembra-capture-tuya-dependencies-v2\""))
        #expect(helper.contains("thing_smart_cryption_podspec_sha256"))
        #expect(helper.contains("thing_smart_cryption_build_tree_sha256"))
        #expect(helper.contains("private_identity_podspec_sha256"))
        #expect(helper.contains("private_identity_sources_tree_sha256"))
        #expect(helper.contains("O_NOFOLLOW"))
        #expect(helper.contains("private Tuya build inputs changed after bootstrap"))
    }

    @Test("V16 signed-build producer re-verifies ignored inputs around archive compilation")
    func signedBuildProducerCannotBuildAcrossPrivateInputDrift() throws {
        let producer = try readRepositoryFile("scripts/field/build_signed_capture_candidate.command")
        let calls = producer.split(separator: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces) == "verify_private_tuya_inputs"
        }
        #expect(calls.count == 2)

        let firstCall = try requiredIndex(
            of: "unset NEMBRA_TUYA_APP_KEY NEMBRA_TUYA_APP_SECRET || true\nverify_private_tuya_inputs",
            in: producer
        )
        let build = try requiredIndex(of: "say \"Building signed standalone Nembra Capture archive\"", in: producer)
        let secondCall = try requiredIndex(of: "\nverify_private_tuya_inputs\n[[ \"$(GIT_NO_REPLACE_OBJECTS=1", in: producer)
        let appReadback = try requiredIndex(of: "APP=\"$ARCHIVE_PATH/Products/Applications/Nembra Capture.app\"", in: producer)

        #expect(firstCall < build)
        #expect(build < secondCall)
        #expect(secondCall < appReadback)
        #expect(producer.contains("--record \"$TUYA_DEPENDENCY_PROVENANCE\""))
        #expect(producer.contains("Private Tuya SDK/app-identity inputs no longer match the bootstrap fingerprint record"))
    }

    @Test("private fingerprint subject stays local instead of becoming public candidate metadata")
    func candidateDoesNotExportCredentialAdjacentFingerprints() throws {
        let producer = try readRepositoryFile("scripts/field/build_signed_capture_candidate.command")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(producer.contains("fingerprint record itself stays under LocalSecrets"))
        #expect(!producer.contains("privateInputProvenanceSHA256"))
        #expect(!producer.contains("private-input-provenance.txt"))
        #expect(producer.contains("\"physicalAuthorityCreated\": False"))
        #expect(helper.contains("cryptographic fingerprints"))
        #expect(helper.contains("It never serializes AppKey/AppSecret"))
        #expect(!producer.contains("app_secret_sha256"))
        #expect(!producer.contains("app_key_sha256"))
    }

    @Test("private provenance stays local and does not serialize secret values")
    func fingerprintRecordDoesNotBecomeCredentialExport() throws {
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        #expect(helper.contains("cryptographic fingerprints"))
        #expect(helper.contains("It never serializes AppKey/AppSecret"))
        #expect(!bootstrap.contains("app_secret_sha256"))
        #expect(!bootstrap.contains("app_key_sha256"))
        #expect(bootstrap.contains("Local private-input fingerprint record"))
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
