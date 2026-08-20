import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary Capture install manifest")
struct AuthenticatedStationaryCaptureInstallManifestTests {
    private typealias Verifier = AuthenticatedStationaryCaptureInstallManifestVerifier
    private typealias ManifestError = AuthenticatedStationaryCaptureInstallManifestError

    private struct TestWire: Codable {
        let schema: String
        let version: Int
        let procedureID: String
        let sourceCommitSHA: String
        let bundleIdentifier: String
        let buildIdentifier: String
        let buildInstanceID: String
        let retainedIPASHA256: String
        let executableSHA256: String
        let infoPlistSHA256: String
        let tuyaDependencyLockSHA256: String
        let externalBuildRecordSHA256: String
        let signedBuildEvidenceSHA256: String
        let finalGORecordSHA256: String
        let intendedDevicePseudonymSHA256: String
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
        buildIdentifier: String? = nil,
        buildInstanceID: String? = nil,
        retainedIPASHA256: String? = nil
    ) -> TestWire {
        let source = sourceCommitSHA ?? self.sourceCommitSHA
        return TestWire(
            schema: Verifier.schema,
            version: Verifier.schemaVersion,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            sourceCommitSHA: source,
            bundleIdentifier: bundleIdentifier ?? Verifier.bundleIdentifier,
            buildIdentifier: buildIdentifier ?? "Capture Build V14-\(source.prefix(12))",
            buildInstanceID: buildInstanceID ?? self.buildInstanceID,
            retainedIPASHA256: retainedIPASHA256 ?? String(repeating: "1", count: 64),
            executableSHA256: executableSHA256,
            infoPlistSHA256: infoPlistSHA256,
            tuyaDependencyLockSHA256: String(repeating: "2", count: 64),
            externalBuildRecordSHA256: String(repeating: "3", count: 64),
            signedBuildEvidenceSHA256: String(repeating: "4", count: 64),
            finalGORecordSHA256: String(repeating: "5", count: 64),
            intendedDevicePseudonymSHA256: String(repeating: "6", count: 64)
        )
    }

    private func canonicalData(_ wire: TestWire) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(wire)
    }

    @Test("canonical manifest binds only stable retained-install inputs")
    func canonicalManifestBindsExactInputs() throws {
        let data = try canonicalData(wire())
        let manifest = try Verifier.decodeCanonical(data)

        #expect(manifest.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(manifest.sourceCommitSHA == sourceCommitSHA)
        #expect(manifest.bundleIdentifier == Verifier.bundleIdentifier)
        #expect(manifest.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(manifest.buildInstanceID == buildInstanceID)
        #expect(manifest.retainedIPASHA256 == String(repeating: "1", count: 64))
        #expect(manifest.canonicalManifestSHA256.utf8.count == 64)

        let bindings = try manifest.externalBindings()
        #expect(bindings.tuyaDependencyLockSHA256 == String(repeating: "2", count: 64))
        #expect(bindings.externalBuildRecordSHA256 == String(repeating: "3", count: 64))
        #expect(bindings.signedBuildEvidenceSHA256 == String(repeating: "4", count: 64))
        #expect(bindings.finalGORecordSHA256 == String(repeating: "5", count: 64))
        #expect(bindings.intendedDevicePseudonymSHA256 == String(repeating: "6", count: 64))
    }

    @Test("Swift verifier vocabulary and strictness stay pinned to the Python mirror")
    func swiftAndPythonManifestContractCannotDrift() throws {
        let python = try Self.repositoryFile("scripts/ci/es80_retained_install_manifest.py")

        #expect(python.contains("SCHEMA = \"\(Verifier.schema)\""))
        #expect(python.contains("SCHEMA_VERSION = \(Verifier.schemaVersion)"))
        #expect(python.contains("BUNDLE_IDENTIFIER = \"\(Verifier.bundleIdentifier)\""))
        #expect(python.contains("\"retainedIPASHA256\""))
        #expect(python.contains("value.get(\"bundleIdentifier\") != BUNDLE_IDENTIFIER"))
        #expect(python.contains("expected_build_identifier = f\"Capture Build V14-{source[:12]}\""))
        #expect(python.contains("or value == \"0\" * 64"))
        #expect(python.contains("-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-"))
        #expect(!python.contains("manifestKind"))
        #expect(!python.contains("signedInstallableSHA256"))
        #expect(!python.contains("\"authorizationEnvelopeSHA256\","))
    }

    @Test("future attempt envelope cannot be smuggled into the pre-install manifest")
    func rejectsFutureAttemptEnvelopeField() throws {
        let data = try canonicalData(wire())
        let canonical = try #require(String(data: data, encoding: .utf8))
        let injected = String(canonical.dropLast())
            + ",\"authorizationEnvelopeSHA256\":\"\(String(repeating: "7", count: 64))\"}"

        #expect(throws: ManifestError.unexpectedManifestField("authorizationEnvelopeSHA256")) {
            try Verifier.decodeCanonical(Data(injected.utf8))
        }
    }

    @Test("manifest can be checked against the build identity measured from the running app")
    func manifestMatchesMeasuredRuntimeBuildIdentity() throws {
        let manifest = try Verifier.decodeCanonical(canonicalData(wire()))
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
        var data = try canonicalData(wire())
        data.append(0x0A)

        #expect(throws: ManifestError.nonCanonicalManifest) {
            try Verifier.decodeCanonical(data)
        }
    }

    @Test("duplicate and unknown fields fail closed before any cross-binding is trusted")
    func rejectsDuplicateAndUnexpectedFields() throws {
        let data = try canonicalData(wire())
        let canonical = try #require(String(data: data, encoding: .utf8))
        let schemaField = "\"schema\":\"\(Verifier.schema)\""
        let duplicated = canonical.replacingOccurrences(
            of: schemaField,
            with: "\(schemaField),\(schemaField)"
        )
        #expect(duplicated != canonical)

        #expect(throws: ManifestError.duplicateManifestField("schema")) {
            try Verifier.decodeCanonical(Data(duplicated.utf8))
        }

        let unexpected = String(canonical.dropLast()) + ",\"callerAuthority\":true}"
        #expect(throws: ManifestError.unexpectedManifestField("callerAuthority")) {
            try Verifier.decodeCanonical(Data(unexpected.utf8))
        }
    }

    @Test("digests and source commit must already be canonical nonzero identities")
    func rejectsNormalizedOrZeroIdentities() throws {
        #expect(throws: ManifestError.invalidDigestField("retainedIPASHA256")) {
            try Verifier.decodeCanonical(canonicalData(
                wire(retainedIPASHA256: String(repeating: "A", count: 64))
            ))
        }

        #expect(throws: ManifestError.invalidDigestField("retainedIPASHA256")) {
            try Verifier.decodeCanonical(canonicalData(
                wire(retainedIPASHA256: String(repeating: "0", count: 64))
            ))
        }

        #expect(throws: ManifestError.invalidSourceCommitSHA) {
            try Verifier.decodeCanonical(canonicalData(
                wire(sourceCommitSHA: sourceCommitSHA.uppercased())
            ))
        }

        #expect(throws: ManifestError.invalidSourceCommitSHA) {
            try Verifier.decodeCanonical(canonicalData(
                wire(sourceCommitSHA: String(repeating: "0", count: 40))
            ))
        }
    }

    @Test("bundle, source-bound build label, and UUIDv4 build instance are exact")
    func runtimeBindingVocabulary() throws {
        #expect(throws: ManifestError.invalidBundleIdentifier) {
            try Verifier.decodeCanonical(canonicalData(
                wire(bundleIdentifier: "com.example.wrong")
            ))
        }

        #expect(throws: ManifestError.invalidBuildIdentifier) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildIdentifier: "Capture Build V14-deadbeefdead")
            ))
        }

        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildInstanceID: "12345678-90ab-zzzz-9234-567890abcdef")
            ))
        }

        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildInstanceID: "12345678-1234-1bcd-8def-123456789abc")
            ))
        }

        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildInstanceID: "12345678-1234-4bcd-1def-123456789abc")
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
