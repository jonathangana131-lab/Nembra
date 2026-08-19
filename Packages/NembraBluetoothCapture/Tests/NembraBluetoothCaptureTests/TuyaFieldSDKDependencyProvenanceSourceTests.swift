import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture private Tuya SDK dependency provenance")
struct TuyaFieldSDKDependencyProvenanceSourceTests {
    @Test("public Tuya SDK inputs are exact-pinned for the physical evidence instrument")
    func publicTuyaSDKIsNotFloating() throws {
        let podfile = try readRepositoryFile("Podfile")

        #expect(podfile.contains("pod 'ThingSmartHomeKit', '7.8.0'"))
        #expect(podfile.contains("pod 'ThingSmartBusinessExtensionKit', '7.8.0'"))
        #expect(!podfile.contains("pod 'ThingSmartHomeKit', '~> 7.8.0'"))
        #expect(!podfile.contains("pod 'ThingSmartBusinessExtensionKit', '~> 7.8.0'"))
    }

    @Test("accepted bootstrap authenticates the existing lock before deployment-only install")
    func bootstrapUsesDeploymentOnlyAcceptedLock() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        #expect(script.contains("if [[ \"$REVIEW_ONLY\" == \"1\" ]]"))
        #expect(script.contains("pod install --repo-update"))
        #expect(script.contains("pod install --deployment --no-repo-update"))
        #expect(!script.contains("\npod update\n"))
        #expect(script.contains("[[ -f Podfile.lock && ! -L Podfile.lock ]]"))
        #expect(script.contains("PREINSTALL_LOCK_SHA256"))
        #expect(script.contains("No dependency command was run"))
        #expect(script.contains("deployment-only install mutated the preauthenticated Podfile.lock"))
        #expect(script.contains("ThingSmartHomeKit (7.8.0)"))
        #expect(script.contains("ThingSmartBusinessExtensionKit (7.8.0)"))

        let preauthentication = try #require(script.range(of: "[[ \"$PREINSTALL_LOCK_SHA256\" == \"$ACCEPTED_LOCK_SHA256\" ]]"))
        let acceptedInstall = try #require(script.range(of: "pod install --deployment --no-repo-update"))
        let postauthentication = try #require(script.range(of: "[[ \"$PREINSTALL_LOCK_SHA256\" == \"$LOCK_SHA256\" ]]"))
        #expect(preauthentication.lowerBound < acceptedInstall.lowerBound)
        #expect(acceptedInstall.lowerBound < postauthentication.lowerBound)
    }

    @Test("review creates opaque private authority while field mode only verifies the exact-source accepted generation")
    func bootstrapPreservesExternallyReviewedPrivateInputAuthority() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(script.contains("run_private_input_provenance()"))
        #expect(script.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" \"$operation\""))
        #expect(script.contains("run_private_input_provenance review --review-key \"$PRIVATE_REVIEW_KEY\""))
        #expect(script.contains("run_private_input_provenance verify-review"))
        #expect(script.contains("Field mode will not create or replace it"))
        #expect(script.contains("externally accepted review commitment"))
        #expect(script.contains("PRIVATE_REVIEW_AUTHORITY_PATH=\"CAPTURE_TUYA_PRIVATE_INPUT_REVIEW_COMMITMENT.txt\""))
        #expect(script.contains("rev-parse \"$EXPECTED_FIELD_SOURCE_SHA:$PRIVATE_REVIEW_AUTHORITY_PATH\""))
        #expect(script.contains("cat-file blob \"$PRIVATE_REVIEW_AUTHORITY_BLOB\""))
        #expect(!script.contains("--field-private-input-commitment"))
        #expect(script.contains("--accepted-commitment \"$ACCEPTED_PRIVATE_INPUT_COMMITMENT\""))
        #expect(script.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(script.contains("--security-podspec \"$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec\""))
        #expect(script.contains("--security-build \"$TUYA_PRIVATE_SDK/Build\""))
        #expect(script.contains("--identity-podspec \"$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec\""))
        #expect(script.contains("--identity-sources \"$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig\""))
        #expect(script.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(script.contains("shasum -a 256 Podfile.lock"))
        #expect(script.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(script.contains("PrivateInputReviewKey.bin"))

        let sourceAuthority = try #require(script.range(of: "PRIVATE_REVIEW_AUTHORITY_BLOB="))
        let preverify = try #require(script.range(of: "if ! run_private_input_provenance verify-review"))
        let acceptedInstall = try #require(script.range(of: "pod install --deployment --no-repo-update"))
        let review = try #require(script.range(of: "REVIEW_COMMITMENT=\"$(run_private_input_provenance review"))
        let secondVerify = try #require(
            script.range(
                of: "private Tuya build inputs changed across dependency installation or no longer match the accepted review commitment"
            )
        )
        #expect(sourceAuthority.lowerBound < preverify.lowerBound)
        #expect(preverify.lowerBound < acceptedInstall.lowerBound)
        #expect(acceptedInstall.lowerBound < review.lowerBound)
        #expect(review.lowerBound < secondVerify.lowerBound)

        #expect(helper.contains("SCHEMA = \"nembra-capture-tuya-dependencies-v2\""))
        #expect(helper.contains("PRIVATE_REVIEW_DOMAIN"))
        #expect(helper.contains("PRIVATE_REVIEW_KEY_BYTES = 32"))
        #expect(helper.contains("hmac.new(key, PRIVATE_REVIEW_DOMAIN + _record_bytes(record), hashlib.sha256)"))
        #expect(helper.contains("private_identity_sources_tree_sha256"))
        #expect(helper.contains("private review key custody is not mode 0600/current-user"))

        #expect(!script.contains("AppSecret=$"))
        #expect(!script.contains("AppKey=$"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
