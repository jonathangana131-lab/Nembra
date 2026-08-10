import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture compiled private-dependency provenance")
struct TuyaCompiledDependencyProvenanceSourceTests {
    @Test("field installer validates and transports the resolved Tuya lock fingerprint")
    func installerTransportsResolvedLockFingerprint() throws {
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")
        let project = try readRepositoryFile("NembraCapture.xcodeproj/project.pbxproj")

        #expect(installer.contains("ResolvedTuyaDependencyProvenance.txt"))
        #expect(installer.contains("Podfile.lock"))
        #expect(installer.contains("podfile_lock_sha256"))
        #expect(installer.contains("NEMBRA_CAPTURE_TUYA_PODFILE_LOCK_SHA256"))
        #expect(project.contains("NembraCaptureTuyaPodfileLockSHA256"))
        #expect(project.contains("$(NEMBRA_CAPTURE_TUYA_PODFILE_LOCK_SHA256)"))
    }

    @Test("authoritative field build identity requires the full dependency fingerprint")
    func buildIdentityRejectsMissingDependencyFingerprint() throws {
        let identity = try readRepositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(identity.contains("tuyaPodfileLockSHA256"))
        #expect(identity.contains("NembraCaptureTuyaPodfileLockSHA256"))
        #expect(identity.contains("tuyaPodfileLockSHA256.count == 64"))
        #expect(identity.contains("isAuthoritativeFieldBuild"))
    }

    @Test("sanitized export carries exact compiled source and dependency provenance together")
    func exportCarriesCompiledDependencyFingerprint() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let export = try section(in: app, from: "struct Export: Codable", to: "struct Event: Codable")
        let prepare = try section(in: app, from: "func prepareExport()", to: "private func resetDiscoverySessionOnly")

        #expect(export.contains("let tuyaPodfileLockSHA256: String"))
        #expect(prepare.contains("tuyaPodfileLockSHA256: buildIdentity.tuyaPodfileLockSHA256"))
        #expect(prepare.contains("schemaVersion: 9"))
    }

    @Test("dependency fingerprint remains non-secret provenance")
    func dependencyFingerprintDoesNotExpandSecretSurface() throws {
        let bootstrap = try readRepositoryFile("Scripts/bootstrap_capture_tuya_sdk.sh")
        let installer = try readRepositoryFile("scripts/field/install_one_time_capture.command")

        #expect(bootstrap.contains("shasum -a 256 Podfile.lock"))
        #expect(bootstrap.contains("podfile_lock_sha256=$LOCK_SHA256"))
        #expect(!installer.contains("NEMBRA_CAPTURE_TUYA_APP_SECRET"))
        #expect(!installer.contains("local_key="))
        #expect(!installer.contains("session_key="))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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
        case sectionMissing
    }
}
