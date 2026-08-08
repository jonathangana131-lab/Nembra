import Foundation

/// Externally sourced build record used for a mechanical provenance comparison.
///
/// Construction is public because the accepted build pipeline / field tooling must eventually load
/// this record from outside the running executable. That means possession of this value is NOT
/// trusted authority and is NEVER sufficient to authorize a physical experiment. The caller must
/// separately establish that the record came from the accepted build process.
public struct PassiveBluetoothCaptureExpectedBuildRecord: Equatable, Sendable {
    public let buildIdentifier: String
    public let sourceCommitSHA: String
    public let executableSHA256: String
    public let experimentRecipeID: PassiveBluetoothExperimentRecipeID

    public init(
        buildIdentifier: String,
        sourceCommitSHA: String,
        executableSHA256: String,
        experimentRecipeID: PassiveBluetoothExperimentRecipeID
    ) {
        self.buildIdentifier = buildIdentifier
        self.sourceCommitSHA = sourceCommitSHA
        self.executableSHA256 = executableSHA256
        self.experimentRecipeID = experimentRecipeID
    }
}

/// Deterministic comparison between direct runtime identity and an externally supplied expected
/// build record.
///
/// `isExactTupleMatch` means only that these four software-provenance fields match. It does not
/// authenticate the record, attest source-to-binary provenance, identify an ES80, or grant GO.
public struct PassiveBluetoothCaptureBuildRecordComparison: Equatable, Sendable {
    public enum Mismatch: String, Equatable, Sendable {
        case invalidExpectedBuildIdentifier
        case invalidExpectedSourceCommitSHA
        case invalidExpectedExecutableSHA256
        case buildIdentifier
        case sourceCommitSHA
        case executableSHA256
        case experimentRecipeID
    }

    public let mismatches: [Mismatch]

    public var isExactTupleMatch: Bool {
        mismatches.isEmpty
    }

    fileprivate init(mismatches: [Mismatch]) {
        self.mismatches = mismatches
    }
}

public enum PassiveBluetoothCaptureBuildRecordComparator {
    public static func compare(
        runtimeIdentity: PassiveBluetoothCaptureRuntimeBuildIdentity,
        experimentRecipe: PassiveBluetoothExperimentRecipe,
        expectedRecord: PassiveBluetoothCaptureExpectedBuildRecord
    ) -> PassiveBluetoothCaptureBuildRecordComparison {
        var mismatches: [PassiveBluetoothCaptureBuildRecordComparison.Mismatch] = []

        guard isValidBuildIdentifier(expectedRecord.buildIdentifier) else {
            mismatches.append(.invalidExpectedBuildIdentifier)
            return .init(mismatches: mismatches)
        }

        guard let expectedCommit = normalizedHex(expectedRecord.sourceCommitSHA, byteCount: 40) else {
            mismatches.append(.invalidExpectedSourceCommitSHA)
            return .init(mismatches: mismatches)
        }

        guard let expectedExecutableDigest = normalizedHex(
            expectedRecord.executableSHA256,
            byteCount: 64
        ) else {
            mismatches.append(.invalidExpectedExecutableSHA256)
            return .init(mismatches: mismatches)
        }

        if runtimeIdentity.buildIdentifier != expectedRecord.buildIdentifier {
            mismatches.append(.buildIdentifier)
        }
        if runtimeIdentity.sourceCommitSHA != expectedCommit {
            mismatches.append(.sourceCommitSHA)
        }
        if runtimeIdentity.executableSHA256 != expectedExecutableDigest {
            mismatches.append(.executableSHA256)
        }
        if experimentRecipe.id != expectedRecord.experimentRecipeID {
            mismatches.append(.experimentRecipeID)
        }

        return .init(mismatches: mismatches)
    }

    private static func isValidBuildIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        guard !value.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar)
        }) else {
            return false
        }
        return true
    }

    private static func normalizedHex(_ value: String, byteCount: Int) -> String? {
        let normalized = value.lowercased()
        guard normalized.utf8.count == byteCount else { return nil }
        guard normalized.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }) else {
            return nil
        }
        return normalized
    }
}
