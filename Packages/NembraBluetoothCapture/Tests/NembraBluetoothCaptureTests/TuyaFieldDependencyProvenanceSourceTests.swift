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

    @Test("normal field bootstrap consumes preaccepted private-input provenance instead of resnapshotting it")
    func privateInputsRequireIndependentPreacceptance() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let guardSource = try readRepositoryFile("Scripts/capture_tuya_private_input_build_guard.py")

        #expect(bootstrap.contains("NEMBRA_CAPTURE_ACCEPTED_TUYA_LOCK_SHA256"))
        #expect(bootstrap.contains("NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256"))
        #expect(bootstrap.contains("pre-bootstrap private-input provenance record does not match the independently accepted SHA-256"))
        #expect(bootstrap.contains("normal field bootstrap requires the pre-reviewed private-input provenance record"))
        #expect(bootstrap.contains("REVIEW MODE ONLY: create a candidate record"))
        #expect(bootstrap.contains("DEPENDENCY + PRIVATE-INPUT CANDIDATE ONLY — NOT FIELD BUILD AUTHORITY"))

        let reviewStart = try #require(bootstrap.range(of: "if [[ \"$REVIEW_ONLY\" == \"1\" ]]; then"))
        let snapshot = try #require(bootstrap.range(of: "\"$PROVENANCE_HELPER\" snapshot"))
        let reviewExit = try #require(bootstrap.range(of: "  exit 0", range: snapshot.upperBound..<bootstrap.endIndex))
        #expect(reviewStart.lowerBound < snapshot.lowerBound)
        #expect(snapshot.lowerBound < reviewExit.lowerBound)
        #expect(bootstrap[..<reviewStart.lowerBound].range(of: "\"$PROVENANCE_HELPER\" snapshot") == nil)
        #expect(bootstrap[reviewExit.upperBound...].range(of: "\"$PROVENANCE_HELPER\" snapshot") == nil)

        #expect(installer.contains("NEMBRA_CAPTURE_ACCEPTED_TUYA_PROVENANCE_SHA256"))
        #expect(installer.contains("record_sha\" == \"$ACCEPTED_TUYA_PROVENANCE_SHA256"))
        #expect(installer.contains("--expected-provenance-sha256 \"$ACCEPTED_TUYA_PROVENANCE_SHA256\""))
        #expect(installer.contains("Normal field mode cannot rebind this authority"))
        #expect(guardSource.contains("def canonical_provenance_sha256(self) -> str"))
        #expect(guardSource.contains("live private build inputs do not match the independently accepted provenance"))
        #expect(guardSource.contains("--expected-provenance-sha256"))
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
            "Podfile.lock",
            "Scripts/bootstrap_capture_tuya_sdk.sh",
            "Scripts/capture_tuya_private_input_provenance.py",
            "Scripts/capture_tuya_private_input_build_guard.py"
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
        #expect(installer.contains("ACCEPTED_TUYA_PROVENANCE_SHA256"))
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