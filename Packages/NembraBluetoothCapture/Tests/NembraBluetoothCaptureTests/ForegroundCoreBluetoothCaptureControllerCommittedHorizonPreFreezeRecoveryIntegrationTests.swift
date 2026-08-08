import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller committed-H pre-freeze recovery integration")
struct ForegroundCoreBluetoothCaptureControllerCommittedHorizonPreFreezeRecoveryIntegrationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controller = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift")
        return try String(contentsOf: controller, encoding: .utf8)
    }

    private static func finalizationMethod(in source: String) throws -> Substring {
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    private func beginTargetSessionIfNeeded",
                range: start..<source.endIndex
            )?.lowerBound
        )
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test("queue-committed Horizon failures quarantine exact H before generic capture failure")
    func committedHorizonFailuresConsumeTypedRecovery() throws {
        let source = try Self.controllerSource()
        let method = try Self.finalizationMethod(in: source)

        let commitOffset = try Self.offset(
            of: "committedHorizon = try recordedHorizon.markBoundaryRecorded(",
            in: method
        )
        let artifactReadOffset = try Self.offset(
            of: "let data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)",
            in: method
        )
        let authorityValidationOffset = try Self.offset(
            of: "try validateBoundaryAuthority(committedHorizon.authority)",
            in: method
        )
        let freezeOffset = try Self.offset(
            of: "try committedHorizon.completeHorizonArtifactFreeze(on: &observationBoundaryQueueGate)",
            in: method
        )
        let recoveryOffset = try Self.offset(
            of: "observationBoundaryQueueGate.abortCommittedHorizonBeforeArtifactFreeze(",
            in: method
        )
        let genericFailureOffset = try Self.offset(
            of: "failCapture(error)",
            in: method
        )

        #expect(commitOffset < artifactReadOffset)
        #expect(artifactReadOffset < authorityValidationOffset)
        #expect(authorityValidationOffset < freezeOffset)
        #expect(freezeOffset < recoveryOffset)
        #expect(recoveryOffset < genericFailureOffset)

        let postCommitRecoveryRegion = method[
            method.index(method.startIndex, offsetBy: artifactReadOffset)..<
            method.index(method.startIndex, offsetBy: genericFailureOffset)
        ]
        #expect(postCommitRecoveryRegion.contains("} catch {"))
        #expect(postCommitRecoveryRegion.contains("abortCommittedHorizonBeforeArtifactFreeze"))
        #expect(postCommitRecoveryRegion.contains("throw error"))
    }

    @Test("successful terminal freeze is never followed by committed-H quarantine")
    func successfulFreezeReturnsBeforeRecoveryCatchCanPromoteAnotherMeaning() throws {
        let source = try Self.controllerSource()
        let method = try Self.finalizationMethod(in: source)

        let freezeOffset = try Self.offset(
            of: "try committedHorizon.completeHorizonArtifactFreeze(on: &observationBoundaryQueueGate)",
            in: method
        )
        let retirementOffset = try Self.offset(
            of: "retireQueuedEvidenceAfterTerminalHorizon()",
            in: method
        )
        let finalizedAuthorityOffset = try Self.offset(
            of: "lastFinalizedArtifactAuthority = committedHorizon.authority",
            in: method
        )
        let returnOffset = try Self.offset(of: "return data", in: method)
        let recoveryOffset = try Self.offset(
            of: "observationBoundaryQueueGate.abortCommittedHorizonBeforeArtifactFreeze(",
            in: method
        )

        #expect(freezeOffset < retirementOffset)
        #expect(retirementOffset < finalizedAuthorityOffset)
        #expect(finalizedAuthorityOffset < returnOffset)
        #expect(returnOffset < recoveryOffset)
    }
}
