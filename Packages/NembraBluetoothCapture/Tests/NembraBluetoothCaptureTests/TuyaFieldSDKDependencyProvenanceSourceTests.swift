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

    @Test("bootstrap preserves lock state and executes the custody adapter only from accepted captured bytes")
    func bootstrapUsesGuardedInstallAndRequiresResolvedLock() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        let acceptedDigest = try #require(script.range(of: ": \"${NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256:?"))
        let adapterIdentity = try #require(script.range(of: "PRIVATE_INPUT_RESOLUTION_GUARD_GIT_BLOB_OID=\""))
        let adapterCapture = try #require(script.range(of: "RESOLUTION_GUARD_CAPTURE=\"$({ /bin/cat -- \"$PRIVATE_INPUT_RESOLUTION_GUARD\";"))
        let guardedInvocation = try #require(script.range(of: "run_private_resolution_guard \\\n"))
        let guardedInstall = try #require(script.range(of: "     \"$POD_BIN\" install --repo-update"))

        #expect(acceptedDigest.lowerBound < adapterCapture.lowerBound)
        #expect(adapterIdentity.lowerBound < adapterCapture.lowerBound)
        #expect(adapterCapture.lowerBound < guardedInvocation.lowerBound)
        #expect(guardedInvocation.lowerBound < guardedInstall.lowerBound)
        #expect(script.contains("printf '%s' \"$RESOLUTION_GUARD_SOURCE\" | /usr/bin/python3 -I -"))
        #expect(!script.contains("/usr/bin/python3 -I \"$PRIVATE_INPUT_RESOLUTION_GUARD\""))
        #expect(!script.contains("\npod install --repo-update\n"))
        #expect(!script.contains("\npod update\n"))
        #expect(script.contains("[[ ! -f Podfile.lock ]]"))
        #expect(script.contains("ThingSmartHomeKit (7.8.0)"))
        #expect(script.contains("ThingSmartBusinessExtensionKit (7.8.0)"))
    }

    @Test("bootstrap snapshots exact private inputs through the captured provenance helper")
    func bootstrapRecordsLockFingerprint() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(script.contains("PROVENANCE_HELPER_GIT_BLOB_OID=\""))
        #expect(script.contains("PROVENANCE_CAPTURE=\"$({ /bin/cat -- \"$PROVENANCE_HELPER\";"))
        #expect(script.contains("/usr/bin/python3 -I -c \"$PROVENANCE_SOURCE\" snapshot"))
        #expect(!script.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" snapshot"))
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