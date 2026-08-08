import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture build record artifact")
struct PassiveBluetoothCaptureBuildRecordArtifactTests {
    private let buildIdentifier = "Capture Build V14-F1"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let digest = "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"

    @Test("schema-v1 artifact round trips deterministically and normalizes hex case")
    func canonicalRoundTrip() throws {
        let json = try makeJSON(
            sourceCommitSHA: commit.uppercased(),
            executableSHA256: digest.uppercased()
        )

        let artifact = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)

        #expect(artifact.schemaVersion == 1)
        #expect(artifact.expectedBuildRecord.buildIdentifier == buildIdentifier)
        #expect(artifact.expectedBuildRecord.sourceCommitSHA == commit)
        #expect(artifact.expectedBuildRecord.executableSHA256 == digest)
        #expect(artifact.expectedBuildRecord.experimentRecipeID == .es80FingerprintV1)
        #expect(artifact.procedureVersion == "V14")
        #expect(artifact.toolchainIdentifier == "Xcode 27")

        let encoded = try PassiveBluetoothCaptureBuildRecordArtifactJSON.encode(artifact)
        let decodedAgain = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(encoded)
        #expect(decodedAgain == artifact)
    }

    @Test("unknown authority-looking field fails closed")
    func unknownAuthorityFieldFailsClosed() throws {
        var object = try validObject()
        object["physicalGo"] = true
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError.unexpectedField("physicalGo")
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)
        }
    }

    @Test("future schema cannot silently acquire current meaning")
    func unsupportedSchemaFailsClosed() throws {
        var object = try validObject()
        object["schemaVersion"] = 2
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError.unsupportedSchemaVersion(2)
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)
        }
    }

    @Test("unknown recipe identifier fails closed")
    func unknownRecipeFailsClosed() throws {
        var object = try validObject()
        object["experimentRecipeID"] = "ES80-FINGERPRINT-v999"
        let json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError
                .invalidExperimentRecipeID("ES80-FINGERPRINT-v999")
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)
        }
    }

    @Test("malformed exact source commit is rejected")
    func malformedCommitFailsClosed() throws {
        let json = try makeJSON(sourceCommitSHA: "main")

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError.invalidSourceCommitSHA("main")
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)
        }
    }

    @Test("malformed executable digest is rejected")
    func malformedExecutableDigestFailsClosed() throws {
        let invalid = String(repeating: "z", count: 64)
        let json = try makeJSON(executableSHA256: invalid)

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError.invalidExecutableSHA256(invalid)
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(json)
        }
    }

    @Test("operator-facing provenance labels are exact and cannot be padded")
    func paddedHumanReadableFieldsFailClosed() throws {
        let paddedBuild = " \(buildIdentifier)"
        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError
                .invalidBuildIdentifier(paddedBuild)
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(
                makeJSON(buildIdentifier: paddedBuild)
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError
                .invalidProcedureVersion("V14 ")
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(
                makeJSON(procedureVersion: "V14 ")
            )
        }

        #expect(
            throws: PassiveBluetoothCaptureBuildRecordArtifactError
                .invalidToolchainIdentifier(" Xcode 27")
        ) {
            _ = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(
                makeJSON(toolchainIdentifier: " Xcode 27")
            )
        }
    }

    @Test("decoded artifact can feed the mechanical runtime comparison without becoming GO")
    func decodedArtifactFeedsComparator() throws {
        let runtime = try PassiveBluetoothCaptureRuntimeBuildIdentityReader.resolveEmbeddedMetadata(
            infoDictionary: [
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.buildIdentifierInfoDictionaryKey:
                    buildIdentifier,
                PassiveBluetoothCaptureRuntimeBuildIdentityReader.sourceCommitSHAInfoDictionaryKey:
                    commit
            ],
            executableData: Data("field executable".utf8)
        )
        let artifact = try PassiveBluetoothCaptureBuildRecordArtifactJSON.decode(
            makeJSON(executableSHA256: runtime.executableSHA256)
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: .es80FingerprintV1,
            expectedRecord: artifact.expectedBuildRecord
        )

        #expect(comparison.isExactTupleMatch)
        #expect(comparison.mismatches.isEmpty)
    }

    private func makeJSON(
        buildIdentifier: String? = nil,
        sourceCommitSHA: String? = nil,
        executableSHA256: String? = nil,
        procedureVersion: String = "V14",
        toolchainIdentifier: String = "Xcode 27"
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "buildIdentifier": buildIdentifier ?? self.buildIdentifier,
                "sourceCommitSHA": sourceCommitSHA ?? commit,
                "executableSHA256": executableSHA256 ?? digest,
                "experimentRecipeID": "ES80-FINGERPRINT-v1",
                "procedureVersion": procedureVersion,
                "toolchainIdentifier": toolchainIdentifier,
            ],
            options: [.sortedKeys]
        )
    }

    private func validObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: makeJSON()) as? [String: Any])
    }
}
