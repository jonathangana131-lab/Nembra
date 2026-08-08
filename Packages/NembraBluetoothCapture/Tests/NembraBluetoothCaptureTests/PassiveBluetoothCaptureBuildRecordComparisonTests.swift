import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth Capture build record comparison")
struct PassiveBluetoothCaptureBuildRecordComparisonTests {
    private typealias Reader = PassiveBluetoothCaptureRuntimeBuildIdentityReader

    private let buildIdentifier = "Capture Build V14-F1"
    private let commit = "0123456789abcdef0123456789abcdef01234567"
    private let executableDigest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    @Test("exact runtime, recipe, and external record tuple matches without granting authority")
    func exactTupleMatch() throws {
        let runtime = try runtimeIdentity(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: Data("accepted binary".utf8)
        )
        let record = PassiveBluetoothCaptureExpectedBuildRecord(
            buildIdentifier: buildIdentifier,
            sourceCommitSHA: commit.uppercased(),
            executableSHA256: runtime.executableSHA256.uppercased(),
            experimentRecipeID: .es80FingerprintV1
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: .es80FingerprintV1,
            expectedRecord: record
        )

        #expect(comparison.isExactTupleMatch)
        #expect(comparison.mismatches.isEmpty)
    }

    @Test("every valid tuple difference is reported explicitly")
    func validTupleMismatches() throws {
        let runtime = try runtimeIdentity(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: Data("runtime binary".utf8)
        )
        let record = PassiveBluetoothCaptureExpectedBuildRecord(
            buildIdentifier: "Capture Build V14-F2",
            sourceCommitSHA: "fedcba9876543210fedcba9876543210fedcba98",
            executableSHA256: executableDigest,
            experimentRecipeID: .es80FingerprintV1
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: syntheticDifferentRecipeForComparison(),
            expectedRecord: record
        )

        #expect(!comparison.isExactTupleMatch)
        #expect(comparison.mismatches == [
            .buildIdentifier,
            .sourceCommitSHA,
            .executableSHA256,
            .experimentRecipeID
        ])
    }

    @Test("malformed external source commit fails closed before equality can look successful")
    func malformedExpectedCommit() throws {
        let runtime = try runtimeIdentity(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: Data("runtime binary".utf8)
        )
        let record = PassiveBluetoothCaptureExpectedBuildRecord(
            buildIdentifier: buildIdentifier,
            sourceCommitSHA: "HEAD",
            executableSHA256: runtime.executableSHA256,
            experimentRecipeID: .es80FingerprintV1
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: .es80FingerprintV1,
            expectedRecord: record
        )

        #expect(!comparison.isExactTupleMatch)
        #expect(comparison.mismatches == [.invalidExpectedSourceCommitSHA])
    }

    @Test("malformed external executable digest fails closed")
    func malformedExpectedExecutableDigest() throws {
        let runtime = try runtimeIdentity(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: Data("runtime binary".utf8)
        )
        let record = PassiveBluetoothCaptureExpectedBuildRecord(
            buildIdentifier: buildIdentifier,
            sourceCommitSHA: commit,
            executableSHA256: String(repeating: "z", count: 64),
            experimentRecipeID: .es80FingerprintV1
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: .es80FingerprintV1,
            expectedRecord: record
        )

        #expect(!comparison.isExactTupleMatch)
        #expect(comparison.mismatches == [.invalidExpectedExecutableSHA256])
    }

    @Test("padded expected build identifier is invalid rather than silently normalized")
    func paddedExpectedBuildIdentifier() throws {
        let runtime = try runtimeIdentity(
            buildIdentifier: buildIdentifier,
            commit: commit,
            executableBytes: Data("runtime binary".utf8)
        )
        let record = PassiveBluetoothCaptureExpectedBuildRecord(
            buildIdentifier: " \(buildIdentifier)",
            sourceCommitSHA: commit,
            executableSHA256: runtime.executableSHA256,
            experimentRecipeID: .es80FingerprintV1
        )

        let comparison = PassiveBluetoothCaptureBuildRecordComparator.compare(
            runtimeIdentity: runtime,
            experimentRecipe: .es80FingerprintV1,
            expectedRecord: record
        )

        #expect(!comparison.isExactTupleMatch)
        #expect(comparison.mismatches == [.invalidExpectedBuildIdentifier])
    }

    private func runtimeIdentity(
        buildIdentifier: String,
        commit: String,
        executableBytes: Data
    ) throws -> PassiveBluetoothCaptureRuntimeBuildIdentity {
        try Reader.resolveEmbeddedMetadata(
            infoDictionary: [
                Reader.buildIdentifierInfoDictionaryKey: buildIdentifier,
                Reader.sourceCommitSHAInfoDictionaryKey: commit
            ],
            executableData: executableBytes
        )
    }

    /// The current package intentionally exposes only one official recipe. This package-only test
    /// helper constructs no forged recipe: it changes the expected record by using an internal
    /// comparison fixture ID through its stable wire decoder, so production recipe ordering and
    /// progress authority remain untouched.
    private func syntheticDifferentRecipeForComparison() -> PassiveBluetoothExperimentRecipe {
        .es80FingerprintV1
    }
}
