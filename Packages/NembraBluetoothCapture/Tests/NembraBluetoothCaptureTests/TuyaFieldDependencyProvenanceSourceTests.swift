import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field dependency provenance")
struct TuyaFieldDependencyProvenanceSourceTests {
    @Test("field installer stamps and reads back the exact resolved Tuya lock fingerprint")
    func installerBindsResolvedLockToBuiltApp() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(installer.contains("shasum -a 256 \"$ROOT/Podfile.lock\""))
        #expect(installer.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256"))
        #expect(installer.contains("plutil -extract NembraCaptureTuyaDependencyLockSHA256"))
        #expect(installer.contains("BUILT_TUYA_DEPENDENCY_LOCK_SHA256\" == \"$TUYA_DEPENDENCY_LOCK_SHA256"))
    }

    @Test("field authority requires both exact source and dependency lock fingerprints")
    func buildIdentityFailsClosedWithoutDependencyProvenance() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        #expect(identity.contains("NembraCaptureTuyaDependencyLockSHA256"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256"))
    }

    @Test("sanitized export carries dependency provenance without private credential material")
    func exportCarriesOnlyNonSecretDependencyFingerprint() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("let tuyaDependencyLockSHA256: String"))
        #expect(app.contains("tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256"))
        #expect(app.contains("schemaVersion: 10"))
        #expect(!app.contains("schemaVersion: 9"))
        #expect(!app.contains("let appSecret: String"))
        #expect(!app.contains("let localKey: String"))
    }

    @Test("field provenance reruns for all standalone Capture sources and dependency inputs")
    func workflowCoversCompiledFieldInputs() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        for path in [
            "NembraApp/App/NembraCaptureBuildIdentity.swift",
            "NembraApp/App/NembraCaptureEntrypoint.swift",
            "NembraApp/Features/Research/TuyaAccountBridge.swift",
            "NembraApp/Features/Research/ES80CaptureShellView.swift",
            "NembraCapture.xcodeproj/project.pbxproj",
            "NembraCapture.xcodeproj/xcshareddata/xcschemes/Nembra Capture.xcscheme",
            "NembraCapture-Info.plist",
            "Packages/NembraBluetoothCapture/**",
            "Packages/NembraCore/**",
            "Podfile",
            "Podfile.lock"
        ] {
            #expect(workflow.contains("- \(path)"))
        }
    }

    @Test("Capture package declares NembraCore as a field-build dependency")
    func capturePackageDependencyRequiresNembraCoreProvenanceAdmission() throws {
        let manifest = try readRepositoryFile("Packages/NembraBluetoothCapture/Package.swift")
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        #expect(manifest.contains(".package(path: \"../NembraCore\")"))
        #expect(manifest.contains(".product(name: \"NembraCore\", package: \"NembraCore\")"))
        #expect(workflow.contains("- Packages/NembraCore/**"))
    }

    @Test("dependency provenance never promotes private SDK credentials into evidence")
    func dependencyFingerprintIsNotASecretFingerprint() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        #expect(installer.contains("Podfile.lock"))
        #expect(!identity.contains("AppSecret"))
        #expect(!identity.contains("local_key"))
        #expect(!identity.contains("appKeySHA"))
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
}