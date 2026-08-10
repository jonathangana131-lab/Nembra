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

    @Test("bootstrap delegates the non-secret dependency record to the custody helper")
    func bootstrapDelegatesLockFingerprintToCustodyHelper() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let helper = try readRepositoryFile("Scripts/capture_tuya_private_input_provenance.py")

        #expect(bootstrap.contains("PROVENANCE_HELPER=\"$SCRIPT_DIR/capture_tuya_private_input_provenance.py\""))
        #expect(bootstrap.contains("/usr/bin/python3 -I \"$PROVENANCE_HELPER\" snapshot"))
        #expect(bootstrap.contains("--lockfile \"$REPO_ROOT/Podfile.lock\""))
        #expect(bootstrap.contains("--record \"$DEPENDENCY_PROVENANCE\""))
        #expect(bootstrap.contains("shasum -a 256 Podfile.lock"))
        #expect(bootstrap.contains("[[ \"$(stat -f '%Lp' \"$DEPENDENCY_PROVENANCE\" 2>/dev/null || true)\" == \"600\" ]]"))

        #expect(helper.contains("SCHEMA = \"nembra-capture-tuya-dependencies-v2\""))
        #expect(helper.contains("\"podfile_lock_sha256\""))
        #expect(helper.contains("os.chmod(temporary_name, 0o600)"))
        #expect(helper.contains("os.chmod(path, 0o600)"))

        #expect(!bootstrap.contains("AppSecret=$"))
        #expect(!bootstrap.contains("AppKey=$"))
        #expect(!helper.contains("AppSecret=$"))
        #expect(!helper.contains("AppKey=$"))
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
