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
        let authorizationEnvelopeSHA256: String
    }

    private let sourceCommitSHA = "0123456789abcdef0123456789abcdef01234567"
    private let buildInstanceID = "12345678-1234-4abc-8def-123456789abc"
    private let executableSHA256 =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let infoPlistSHA256 =
        "06efe9fe27056463478429afb2c47cc02f0096f2d4ec4282b38df88cb9e4b1b0"

    private func wire(
        bundleIdentifier: String? = nil,
        sourceCommitSHA: String? = nil,
        buildIdentifier: String? = nil,
        buildInstanceID: String? = nil,
        retainedIPASHA256: String? = nil
    ) -> TestWire {
        let sourceCommitSHA = sourceCommitSHA ?? self.sourceCommitSHA
        return TestWire(
            schema: Verifier.schema,
            version: Verifier.schemaVersion,
            procedureID: AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID,
            sourceCommitSHA: sourceCommitSHA,
            bundleIdentifier: bundleIdentifier ?? Verifier.bundleIdentifier,
            buildIdentifier: buildIdentifier ?? "Capture Build V14-\(sourceCommitSHA.prefix(12))",
            buildInstanceID: buildInstanceID ?? self.buildInstanceID,
            retainedIPASHA256: retainedIPASHA256 ?? String(repeating: "1", count: 64),
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

    private func canonicalData(_ wire: TestWire) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(wire)
    }

    @Test("canonical manifest binds the retained install candidate and authorization inputs")
    func canonicalManifestBindsExactInputs() throws {
        let data = try canonicalData(wire())
        let manifest = try Verifier.decodeCanonical(data)

        #expect(manifest.procedureID == AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID)
        #expect(manifest.sourceCommitSHA == sourceCommitSHA)
        #expect(manifest.bundleIdentifier == Verifier.bundleIdentifier)
        #expect(manifest.buildIdentifier == "Capture Build V14-0123456789ab")
        #expect(manifest.buildInstanceID == buildInstanceID)
        #expect(manifest.retainedIPASHA256 == String(repeating: "1", count: 64))
        #expect(manifest.authorizationEnvelopeSHA256 == String(repeating: "7", count: 64))
        #expect(manifest.canonicalManifestSHA256.utf8.count == 64)

        let bindings = try manifest.externalBindings()
        #expect(bindings.tuyaDependencyLockSHA256 == String(repeating: "2", count: 64))
        #expect(bindings.externalBuildRecordSHA256 == String(repeating: "3", count: 64))
        #expect(bindings.signedBuildEvidenceSHA256 == String(repeating: "4", count: 64))
        #expect(bindings.finalGORecordSHA256 == String(repeating: "5", count: 64))
        #expect(bindings.intendedDevicePseudonymSHA256 == String(repeating: "6", count: 64))
    }

    @Test("manifest enforces the same identity semantics as the retained installer contract")
    func installerSemanticParity() throws {
        #expect(throws: ManifestError.invalidBundleIdentifier) {
            try Verifier.decodeCanonical(canonicalData(
                wire(bundleIdentifier: "com.example.capture")
            ))
        }
        #expect(throws: ManifestError.invalidSourceCommitSHA) {
            try Verifier.decodeCanonical(canonicalData(
                wire(sourceCommitSHA: String(repeating: "0", count: 40))
            ))
        }
        #expect(throws: ManifestError.invalidBuildIdentifier) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildIdentifier: "Capture Build V14-fedcba987654")
            ))
        }
        #expect(throws: ManifestError.invalidBuildIdentifier) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildIdentifier: "capture-v14-0123456789ab")
            ))
        }
        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildInstanceID: "12345678-1234-1abc-8def-123456789abc")
            ))
        }
        #expect(throws: ManifestError.invalidBuildInstanceID) {
            try Verifier.decodeCanonical(canonicalData(
                wire(buildInstanceID: "12345678-1234-4abc-7def-123456789abc")
            ))
        }
        #expect(throws: ManifestError.invalidDigestField("retainedIPASHA256")) {
            try Verifier.decodeCanonical(canonicalData(
                wire(retainedIPASHA256: String(repeating: "0", count: 64))
            ))
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

    @Test("digests and source commit must already be canonical lowercase identities")
    func rejectsNormalizedAfterTheFactIdentities() throws {
        #expect(throws: ManifestError.invalidDigestField("retainedIPASHA256")) {
            try Verifier.decodeCanonical(canonicalData(
                wire(retainedIPASHA256: String(repeating: "A", count: 64))
            ))
        }

        #expect(throws: ManifestError.invalidSourceCommitSHA) {
            try Verifier.decodeCanonical(canonicalData(
                wire(sourceCommitSHA: sourceCommitSHA.uppercased())
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
}
