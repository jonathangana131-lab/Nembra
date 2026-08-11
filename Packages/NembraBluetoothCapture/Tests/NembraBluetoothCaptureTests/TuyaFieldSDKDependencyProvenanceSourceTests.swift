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

    @Test("bootstrap records a non-secret lock fingerprint for field provenance")
    func bootstrapRecordsLockFingerprint() throws {
        let script = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")

        #expect(script.contains("shasum -a 256 Podfile.lock"))
        #expect(script.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(script.contains("schema=nembra-capture-tuya-dependencies-v1"))
        #expect(script.contains("podfile_lock_sha256=$LOCK_SHA256"))
        #expect(script.contains("chmod 600 \"$DEPENDENCY_PROVENANCE\""))
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
