import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary Capture install manifest")
struct AuthenticatedStationaryCaptureInstallManifestTests {
    private typealias Verifier = AuthenticatedStationaryCaptureInstallManifestVerifier
    private typealias ManifestError = AuthenticatedStationaryCaptureInstallManifestError

    private struct TestWire {
        let schema: String
        let version: Int
        let manifestKind: String
        let procedureID: String
        let sourceCommitSHA: String
        let bundleIdentifier: String
        let buildIdentifier: String
        let buildInstanceID: String
        let signedInstallableSHA256: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let signedBuildEvidenceSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
        let authorizationEnvelopeSHA256: String
    }

    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-90ab-4def-9234-567890abcdef"
    private let executableSHA256 =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let infoPlistSHA256 =
        "06efe9fe27056463478429afb2c47cc02f0096f2d4ec4282b38df88cb9e4b1b0"

    private func wire(
        sourceCommitSHA: String? = nil,
        bundleIdentifier: String? = nil,
        buildInstanceID: String? = nil,
        signedInstallableSHA256: String? = nil
    ) -> TestWire {
        TestWire(
            schema: Verifier.schema,
            version: Verifier.schemaVersion,
            manifestKind: Verifier.manifestKind,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            sourceCommitSHA: sourceCommitSHA ?? self.sourceCommitSHA,
            bundleIdentifier: bundleIdentifier ?? Verifier.bundleIdentifier,
            buildIdentifier: "Capture Build V14-0123456789ab",
            buildInstanceID: buildInstanceID ?? self.buildInstanceID,
            signedInstallableSHA256: signedInstallableSHA256 ?? String(repeating: "1", count: 64),
            executableSHA256: executableSHA256,
            infoPlistSHA256: infoPlistSHA256,
            tuyaDependencyLockSHA256: String(repeating: "2", count: 64),
            externalBuildRecordSHA256: String(repeating: "3", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "4", count: 64),
            finalGORecordSHA256: String(repeating: "5", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "6", count: 64),
            authorizationEnvelopeSHA256: String(repeating: "7", count: 64)
        )
    }

    private func canonicalPythonData(_ wire: TestWire) throws -> Data {
        let fields: [(String, String)] = [
            ("schema", try jsonString(wire.schema)),
            ("version", String(wire.version)),
            ("manifestKind", try jsonString(wire.manifestKind)),
            ("procedureID", try jsonString(wire.procedureID)),
            ("sourceCommitSHA", try jsonString(wire.sourceCommitSHA)),
            ("bundleIdentifier", try jsonString(wire.bundleIdentifier)),
            ("buildIdentifier", try jsonString(wire.buildIdentifier)),
            ("buildInstanceID", try jsonString(wire.buildInstanceID)),
            ("signedInstallableSHA256", try jsonString(wire.signedInstallableSHA256)),
            ("executableSHA256", try jsonString(wire.executableSHA256)),
            ("infoPlistSHA256", try jsonString(wire.infoPlistSHA256)),
            ("tuyaDependencyLockSHA256", try jsonString(wire.tuyaDependencyLockSHA256)),
            ("externalBuildRecordSHA256", try jsonString(wire.externalBuildRecordSHA256)),
            ("signedBuildEvidenceSHA256", try jsonString(wire.signedBuildEvidenceSHA256)),
            ("finalGORecordSHA256", try jsonString(wire.finalGORecordSHA256)),
            ("intendedDevicePseudonymSHA256", try jsonString(wire.intendedDevicePseudonymSHA256)),
            ("authorizationEnvelopeSHA256", try jsonString(wire.authorizationEnvelopeSHA256)),
        ].sorted { $0.0 < $1.0 }

        var lines = ["{"]
        for (index, field) in fields.enumerated() {
            lines.append("  \(try jsonString(field.0)): \(field.1)\(index == fields.count - 1 ? "" : ",")")
        }
        lines.append("}")
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func jsonString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes])
        let array = try #require(String(data: data, encoding: .utf8))
        return String(array.dropFirst().dropLast())
    }

    @Test("canonical Python manifest binds the retained install candidate and authorization inputs")
    func canonicalManifestBindsExactInputs() throws {
        let data = try canonicalPythonData(wire())
        let manifest = try Verifier.decodeCanonical(data)

        #expect(manifest.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(manifest.sourceCommitSHA == sourceCommitSHA)
        #expect(manifest.bundleIdentifier == Verifier.bundleIdentifier)
        #expect(manifest.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(manifest.buildInstanceID == buildInstanceID)
        #expect(manifest.signedInstallableSHA256 == String(repeating: "1", count: 64))
        #expect(manifest.authorizationEnvelopeSHA256 == String(repeating: "7", count: 64))
        #expect(manifest.canonicalManifestSHA256.utf8.count == 64)

        let bindings = try manifest.externalBindings()
        #expect(bindings.tuyaDependencyLockSHA256 == String(repeating: "2", count: 64))
        #expect(bindings.externalBuildRecordSHA256 == String(repeating: "3", count: 64))
        #expect(bindings.signedBuildEvidenceSHA256 == String(repeating: "4", count: 64))
        #expect(bindings.finalGORecordSHA256 == String(repeating: "5", count: 64))
        #expect(bindings.intendedDevicePseudonymSHA256 == String(repeating: "6", count: 64))
    }

    @Test("Swift verifier vocabulary is pinned to the Python manifest producer")
    func swiftAndPythonManifestVocabularyCannotDrift() throws {
        let python = try Self.repositoryFile("scripts/ci/es80_retained_install_manifest.py")

        #expect(python.contains("SCHEMA = \"\(Verifier.schema)\""))
        #expect(python.contains("SCHEMA_VERSION = \(Verifier.schemaVersion)"))
        #expect(python.contains("MANIFEST_KIND = \"\(Verifier.manifestKind)\""))
        #expect(python.contains("BUNDLE_IDENTIFIER = \"\(Verifier.bundleIdentifier)\""))
        #expect(python.contains("\"signedInstallableSHA256\""))
        #expect(!python.contains("retainedIPASHA256"))
    }

    @Test("manifest can be checked against the build identity measured from the running app")
    func manifestMatchesMeasuredRuntimeBuildIdentity() throws {
        let manifest = try Verifier.decodeCanonical(canonicalPythonData(wire()))
        let identity = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    "Capture Build V14-0123456789ab",
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey:
                    buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    sourceCommitSHA,
            ],
            executableData: Data("abc".utf8),
            infoPlistData: Data("plist-a".utf8)
        )

        #expect(manifest.matches(runtimeBuildIdentity: identity))
    }

    @Test("non-canonical bytes cannot acquire a retained manifest identity")
    func rejectsNonCanonicalBytes() throws {
        var data = try canonicalPythonData(wire())
        data.removeLast()

        #expect(throws: ManifestError.nonCanonicalManifest) {
            try Verifier.decodeCanonical(data)
        }
    }

    @Test("duplicate and unknown fields fail closed before any cross-binding is trusted")
    func rejectsDuplicateAndUnexpectedFields() throws {
        let data = try canonicalPythonData(wire())
        let canonical = try #require(String(data: data, encoding: .utf8))
        let schemaLine = "  \"schema\": \"\(Verifier.schema)\","
        let duplicated = canonical.replacingOccurrences(
            of: schemaLine,
            with: "\(schemaLine)\n\(schemaLine)"
        )
        #expect(duplicated != canonical)

        #expect(throws: ManifestError.duplicateManifestField("schema")) {
            try Verifier.decodeCanonical(Data(duplicated.utf8))
        }

        let unexpected = canonical.replacingOccurrences(
            of: "{\n",
            with: "{\n  \"callerAuthority\": true,\n"
        )
        #expect(throws: ManifestError.unexpectedManifestField("callerAuthority")) {
            try Verifier.decodeCanonical(Data(unexpected.utf8))
        }
    }

    @Test("digests, source commit, bundle, and build instance must already be canonical")
    func rejectsNormalizedAfterTheFactIdentities() throws {
        #expect(throws: ManifestError.invalidDigestField("signedInstallableSHA256")) {
            try Verifier.decodeCanonical(canonicalPythonData(
                wire(signedInstallableSHA256: String(repeating: "A", count: 64))
            ))
        }

        #expect(throws: ManifestError.invalidDigestField("signedInstallableSHA256")) {
            try Verifier.decodeCanonical(canonicalPythonData(
                wire(signedInstallableSHA256: String(repeating: "0", count: 64))
            ))
        }

        #expect(throws: ManifestError.invalidSourceCommitSHA) {
            try Verifier.decodeCanonical(canonicalPythonData(
                wire(sourceCommitSHA: sourceCommitSHA.uppercased())
            ))
        }

        #expect(throws: ManifestError.invalidBundleIdentifier) {
            try Verifier.decodeCanonical(canonicalPythonData(
                wire(bundleIdentifier: "com.example.wrong")
            ))
        }

        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalPythonData(
                wire(buildInstanceID: "12345678-90ab-1def-9234-567890abcdef")
            ))
        }
    }

    @Test("manifest input is bounded before JSON parsing")
    func manifestInputIsBounded() {
        #expect(throws: ManifestError.inputByteLimitExceeded) {
            try Verifier.decodeCanonical(
                Data(repeating: 0x20, count: Verifier.maximumManifestByteCount + 1)
            )
        }
    }

    private static func repositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
