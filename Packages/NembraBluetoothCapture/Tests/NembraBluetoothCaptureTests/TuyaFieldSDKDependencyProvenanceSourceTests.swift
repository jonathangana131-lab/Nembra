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

    @Test("review may snapshot private inputs but field mode only verifies the pre-existing witness")
    func bootstrapPreservesReviewedPrivateInputWitness() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(script.contains("run_private_input_provenance()"))
        #expect(script.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" \"$operation\""))
        #expect(script.contains("if ! run_private_input_provenance snapshot; then"))
        #expect(script.contains("if ! run_private_input_provenance verify; then"))
        #expect(script.contains("field mode will not create or replace this witness"))
        #expect(script.contains("The reviewed witness was not replaced"))
        #expect(script.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(script.contains("--security-podspec \"$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec\""))
        #expect(script.contains("--security-build \"$TUYA_PRIVATE_SDK/Build\""))
        #expect(script.contains("--identity-podspec \"$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec\""))
        #expect(script.contains("--identity-sources \"$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig\""))
        #expect(script.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(script.contains("shasum -a 256 Podfile.lock"))
        #expect(script.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(script.contains("stat -f '%Lp' \"$DEPENDENCY_PROVENANCE\""))

        let preverify = try #require(script.range(of: "if ! run_private_input_provenance verify; then"))
        let acceptedInstall = try #require(script.range(of: "pod install --deployment --no-repo-update"))
        let reviewSnapshot = try #require(script.range(of: "if ! run_private_input_provenance snapshot; then"))
        let secondVerify = try #require(
            script.range(
                of: "private Tuya build inputs changed across dependency installation. The reviewed witness was not replaced."
            )
        )
        #expect(preverify.lowerBound < acceptedInstall.lowerBound)
        #expect(acceptedInstall.lowerBound < reviewSnapshot.lowerBound)
        #expect(reviewSnapshot.lowerBound < secondVerify.lowerBound)

        #expect(helper.contains("SCHEMA = \"nembra-capture-tuya-dependencies-v2\""))
        #expect(helper.contains("\"podfile_lock_sha256\": _read_stable_regular_file_sha256(lockfile)[1]"))
        #expect(helper.contains("os.chmod(path, 0o600)"))
        #expect(helper.contains("private_identity_sources_tree_sha256"))

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
