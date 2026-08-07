import Foundation

/// Deterministic cardinality summary over one already-built framing-candidate
/// report. These are analyzer outcome counts only; they do not promote a
/// completed candidate into a verified physical ES80 message or telemetry field.
public struct PassiveBluetoothTuyaCaptureOutcomeSummary: Equatable, Codable, Sendable {
    public let streamCount: Int
    public let fragmentCount: Int
    public let completedCandidateCount: Int
    public let rejectedCandidateCount: Int
    public let incompleteAtBoundaryCount: Int
    public let incompleteAtEndCount: Int
    public let unexpectedAnalyzerFailureCount: Int

    public var incompleteCandidateCount: Int {
        incompleteAtBoundaryCount + incompleteAtEndCount
    }
}

public extension PassiveBluetoothTuyaCaptureReport {
    var outcomeSummary: PassiveBluetoothTuyaCaptureOutcomeSummary {
        var fragmentCount = 0
        var completedCandidateCount = 0
        var rejectedCandidateCount = 0
        var incompleteAtBoundaryCount = 0
        var incompleteAtEndCount = 0
        var unexpectedAnalyzerFailureCount = 0

        for stream in streams {
            fragmentCount += stream.fragmentCount
            for event in stream.events {
                switch event.kind {
                case .completed:
                    completedCandidateCount += 1
                case .rejectedCandidate:
                    rejectedCandidateCount += 1
                case .incompleteAtBoundary:
                    incompleteAtBoundaryCount += 1
                case .incompleteAtEnd:
                    incompleteAtEndCount += 1
                case .unexpectedAnalyzerFailure:
                    unexpectedAnalyzerFailureCount += 1
                }
            }
        }

        return PassiveBluetoothTuyaCaptureOutcomeSummary(
            streamCount: streams.count,
            fragmentCount: fragmentCount,
            completedCandidateCount: completedCandidateCount,
            rejectedCandidateCount: rejectedCandidateCount,
            incompleteAtBoundaryCount: incompleteAtBoundaryCount,
            incompleteAtEndCount: incompleteAtEndCount,
            unexpectedAnalyzerFailureCount: unexpectedAnalyzerFailureCount
        )
    }
}
