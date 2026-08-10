import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture field dependency provenance")
struct TuyaFieldDependencyProvenanceSourceTests {
    @Test("field installer stamps the exact resolved Tuya lock fingerprint")
    func installerBindsResolvedLockToCompiledApp() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        #expect(installer.contains("shasum -a 256 \"$ROOT/Podfile.lock\""))
        #expect(installer.contains("TUYA_DEPENDENCY_LOCK_SHA256"))
        #expect(installer.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=$TUYA_DEPENDENCY_LOCK_SHA256"))
    }

    @Test("field authority requires both exact source and dependency lock fingerprints")
    func buildIdentityFailsClosedWithoutDependencyProvenance() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        #expect(identity.contains("NembraCaptureTuyaDependencyLockSHA256"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(project.contains("INFOPLIST_KEY_NembraCaptureTuyaDependencyLockSHA256"))
    }

    @Test("sanitized export carries dependency provenance without credential material")
    func exportCarriesOnlyNonSecretDependencyFingerprint() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("let tuyaDependencyLockSHA256: String"))
        #expect(app.contains("tuyaDependencyLockSHA256: buildIdentity.tuyaDependencyLockSHA256"))
        #expect(app.contains("schemaVersion: 9"))
        #expect(!app.contains("let appSecret: String"))
        #expect(!app.contains("let localKey: String"))
    }

    @Test("exact-head provenance gate verifies the compiled Info plist fingerprint")
    func xcodeGateExercisesDependencyStamp() throws {
        let workflow = try readRepositoryFile(".github/workflows/capture-field-build-provenance.yml")
        #expect(workflow.contains("NEMBRA_CAPTURE_TUYA_DEPENDENCY_LOCK_SHA256=\"$dependency_sha\""))
        #expect(workflow.contains("plutil -extract NembraCaptureTuyaDependencyLockSHA256"))
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
