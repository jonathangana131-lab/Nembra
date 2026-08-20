import CryptoKit
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary Capture signed-build evidence")
struct AuthenticatedStationaryCaptureSignedBuildEvidenceTests {
    private let sourceSHA = String(repeating: "1", count: 40)
    private let buildInstanceID = "12345678-1234-4234-9234-123456789abc"
    private let buildIdentifier = "Capture Build V14-111111111111"
    private let executableData = Data("exact executable".utf8)
    private let infoPlistData = Data("exact plist".utf8)

    @Test("canonical Python evidence reconstructs later authorization bindings")
    func canonicalEvidenceDecodesAndReconstructsAuthorizationBindings() throws {
        let data = try canonicalEvidence()
        let evidence = try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(data)
        #expect(evidence.canonicalEvidenceSHA256 == sha256Hex(data))
        let bindings = try evidence.externalBindings()
        #expect(bindings.tuyaDependencyLockSHA256 == String(repeating: "5", count: 64))
        #expect(bindings.externalBuildRecordSHA256 == String(repeating: "6", count: 64))
        #expect(bindings.signedBuildEvidenceSHA256 == sha256Hex(data))
        #expect(bindings.finalGORecordSHA256 == String(repeating: "7", count: 64))
        #expect(bindings.intendedDevicePseudonymSHA256 == String(repeating: "8", count: 64))
    }

    @Test("equivalent JSON bytes are not canonical evidence bytes")
    func exactPythonStyleCanonicalBytesAreRequired() throws {
        let canonical = try canonicalEvidence()
        let nonCanonical = Data(
            String(decoding: canonical, as: UTF8.self)
                .replacingOccurrences(of: "  \"buildIdentifier\":", with: "    \"buildIdentifier\":")
                .utf8
        )
        #expect(throws: AuthenticatedStationaryCaptureSignedBuildEvidenceError.nonCanonicalEvidence) {
            try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(nonCanonical)
        }
    }

    @Test("duplicate and caller-added fields fail closed")
    func duplicateAndUnexpectedFieldsFailClosed() throws {
        let canonical = String(decoding: try canonicalEvidence(), as: UTF8.self)
        let duplicate = Data(canonical.replacingOccurrences(
            of: "{\n", with: "{\n  \"buildIdentifier\": \"forged\",\n"
        ).utf8)
        #expect(throws: AuthenticatedStationaryCaptureSignedBuildEvidenceError.duplicateEvidenceField("buildIdentifier")) {
            try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(duplicate)
        }

        let unexpected = Data(canonical.replacingOccurrences(
            of: "{\n", with: "{\n  \"callerAuthority\": true,\n"
        ).utf8)
        #expect(throws: AuthenticatedStationaryCaptureSignedBuildEvidenceError.unexpectedEvidenceField("callerAuthority")) {
            try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(unexpected)
        }
    }

    @Test("invalid digests, UUIDs, or running build tuples fail closed")
    func malformedOrWrongRuntimeEvidenceFailsClosed() throws {
        let zeroDigest = try canonicalEvidence(overrides: [
            "finalGORecordSHA256": try jsonString(String(repeating: "0", count: 64)),
        ])
        #expect(throws: AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidDigestField("finalGORecordSHA256")) {
            try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(zeroDigest)
        }

        let nonV4 = try canonicalEvidence(overrides: [
            "buildInstanceID": try jsonString("12345678-1234-5234-9234-123456789abc"),
        ])
        #expect(throws: AuthenticatedStationaryCaptureSignedBuildEvidenceError.invalidBuildInstanceID) {
            try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.decodeCanonical(nonV4)
        }

        let evidence = try AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier
            .decodeCanonical(canonicalEvidence())
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildInstanceIDInfoDictionaryKey: buildInstanceID,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey: sourceSHA,
            ],
            executableData: executableData,
            infoPlistData: infoPlistData
        )
        #expect(evidence.matches(
            runtimeBuildIdentity: runtime,
            bundleIdentifier: AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.expectedBundleIdentifier
        ))
        #expect(!evidence.matches(runtimeBuildIdentity: runtime, bundleIdentifier: "com.attacker.capture"))
    }

    private func canonicalEvidence(overrides: [String: String] = [:]) throws -> Data {
        var values: [String: String] = [
            "buildIdentifier": try jsonString(buildIdentifier),
            "buildInstanceID": try jsonString(buildInstanceID),
            "bundleIdentifier": try jsonString(AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.expectedBundleIdentifier),
            "evidenceKind": try jsonString(AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.evidenceKind),
            "executableSHA256": try jsonString(sha256Hex(executableData)),
            "externalBuildRecordSHA256": try jsonString(String(repeating: "6", count: 64)),
            "finalGORecordSHA256": try jsonString(String(repeating: "7", count: 64)),
            "infoPlistSHA256": try jsonString(sha256Hex(infoPlistData)),
            "intendedDevicePseudonymSHA256": try jsonString(String(repeating: "8", count: 64)),
            "procedureID": try jsonString(AuthenticatedStationaryCaptureFieldAuthorizationVerifier.procedureID),
            "schemaVersion": "1",
            "signedInstallableKind": try jsonString(AuthenticatedStationaryCaptureSignedBuildEvidenceVerifier.signedInstallableKind),
            "signedInstallableSHA256": try jsonString(String(repeating: "4", count: 64)),
            "sourceCommitSHA": try jsonString(sourceSHA),
            "tuyaDependencyLockSHA256": try jsonString(String(repeating: "5", count: 64)),
        ]
        for (key, value) in overrides { values[key] = value }
        let keys = values.keys.sorted()
        var lines: [String] = []
        for (index, key) in keys.enumerated() {
            lines.append("  \(try jsonString(key)): \(values[key]!)\(index + 1 == keys.count ? "" : ",")")
        }
        return Data(("{\n" + lines.joined(separator: "\n") + "\n}\n").utf8)
    }

    private func jsonString(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}