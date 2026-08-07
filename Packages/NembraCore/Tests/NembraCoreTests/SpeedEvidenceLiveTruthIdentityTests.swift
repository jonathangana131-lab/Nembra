import Foundation
import Testing
@testable import NembraCore

@Suite("Speed live-truth token identity")
struct SpeedEvidenceLiveTruthIdentityTests {
    private let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)

    private func expectSuccess(
        _ result: Result<Void, SpeedEvidenceLiveTruthRejection>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        if case let .failure(error) = result {
            Issue.record("Expected success, got \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test("fresh owners cannot mint equal tokens from identical public counters")
    func freshOwnersHaveDistinctOpaqueIdentity() throws {
        var first = SpeedEvidenceLiveTruth()
        var second = SpeedEvidenceLiveTruth()

        expectSuccess(first.beginConnectedGeneration(generation))
        expectSuccess(second.beginConnectedGeneration(generation))

        let firstToken = try #require(first.activeContinuityToken)
        let secondToken = try #require(second.activeContinuityToken)

        #expect(firstToken.connectionGeneration == secondToken.connectionGeneration)
        #expect(firstToken.segmentSequence == secondToken.segmentSequence)
        #expect(firstToken != secondToken)
    }

    @Test("copied owners that rotate independently mint distinct successor tokens")
    func copiedOwnersDoNotCollideAfterDivergence() throws {
        var first = SpeedEvidenceLiveTruth()
        expectSuccess(first.beginConnectedGeneration(generation))
        let sharedToken = try #require(first.activeContinuityToken)

        var second = first
        #expect(second.activeContinuityToken == sharedToken)

        expectSuccess(first.markEvidenceGap(after: sharedToken))
        expectSuccess(second.markEvidenceGap(after: sharedToken))

        let firstSuccessor = try #require(first.activeContinuityToken)
        let secondSuccessor = try #require(second.activeContinuityToken)

        #expect(firstSuccessor.connectionGeneration == secondSuccessor.connectionGeneration)
        #expect(firstSuccessor.segmentSequence == secondSuccessor.segmentSequence)
        #expect(firstSuccessor.segmentSequence == sharedToken.segmentSequence + 1)
        #expect(firstSuccessor != secondSuccessor)
    }

    @Test("recreated owner rejects predecessor token even when diagnostics match")
    func recreatedOwnerRejectsDelayedPredecessorToken() throws {
        var predecessor = SpeedEvidenceLiveTruth()
        expectSuccess(predecessor.beginConnectedGeneration(generation))
        let predecessorToken = try #require(predecessor.activeContinuityToken)

        var recreated = SpeedEvidenceLiveTruth()
        expectSuccess(recreated.beginConnectedGeneration(generation))
        let recreatedToken = try #require(recreated.activeContinuityToken)

        #expect(predecessorToken.connectionGeneration == recreatedToken.connectionGeneration)
        #expect(predecessorToken.segmentSequence == recreatedToken.segmentSequence)
        #expect(predecessorToken != recreatedToken)

        let delayedSample = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: 0,
            receivedAtUptimeNanoseconds: 100,
            receivedAtDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let rejected = recreated.accept(
            delayedSample,
            attributedTo: predecessorToken
        )
        #expect(rejected == .failure(.continuityTokenMismatch))
        #expect(recreated.availability == .unavailable)

        expectSuccess(recreated.accept(delayedSample, attributedTo: recreatedToken))
        #expect(recreated.availability == .live(delayedSample))
    }
}
