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

    @Test("bootstrap preserves lock state instead of silently upgrading dependencies")
    func bootstrapUsesInstallAndRequiresResolvedLock() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        #expect(script.contains("pod install --repo-update"))
        #expect(!script.contains("\npod update\n"))
        #expect(script.contains("[[ ! -f Podfile.lock ]]"))
        #expect(script.contains("ThingSmartHomeKit (7.8.0)"))
        #expect(script.contains("ThingSmartBusinessExtensionKit (7.8.0)"))
    }

    @Test("bootstrap delegates exact private-input fingerprinting to the hardened provenance helper")
    func bootstrapRecordsLockFingerprint() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(script.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" snapshot"))
        #expect(script.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(script.contains("--security-podspec \"$TUYA_PRIVATE_SDK/ThingSmartCryption.podspec\""))
        #expect(script.contains("--security-build \"$TUYA_PRIVATE_SDK/Build\""))
        #expect(script.contains("--identity-podspec \"$TUYA_PRIVATE_IDENTITY/NembraTuyaPrivateConfig.podspec\""))
        #expect(script.contains("--identity-sources \"$TUYA_PRIVATE_IDENTITY/Sources/NembraTuyaPrivateConfig\""))
        #expect(script.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(script.contains("shasum -a 256 Podfile.lock"))
        #expect(script.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(script.contains("stat -f '%Lp' \"$DEPENDENCY_PROVENANCE\""))

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