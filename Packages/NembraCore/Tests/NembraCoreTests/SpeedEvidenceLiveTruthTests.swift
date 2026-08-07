import Foundation
import Testing
@testable import NembraCore

@Suite("Field-specific speed live truth")
struct SpeedEvidenceLiveTruthTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(
        source: SpeedTelemetrySource = .scooterBluetooth,
        provenance: SpeedTelemetryProvenance = .absoluteMeasurement,
        kilometersPerHour: Double,
        uptimeNanoseconds: UInt64
    ) throws -> SpeedTelemetrySample {
        try SpeedTelemetrySample(
            source: source,
            provenance: provenance,
            metersPerSecond: kilometersPerHour / 3.6,
            receivedAtUptimeNanoseconds: uptimeNanoseconds,
            receivedAtDate: epoch.addingTimeInterval(Double(uptimeNanoseconds) / 1_000_000_000)
        )
    }

    private func expectSuccess(
        _ result: Result<Void, SpeedEvidenceLiveTruthRejection>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        if case let .failure(error) = result {
            Issue.record("Expected success, got \(error)", sourceLocation: sourceLocation)
        }
    }

    private func expectFailure(
        _ expected: SpeedEvidenceLiveTruthRejection,
        _ result: Result<Void, SpeedEvidenceLiveTruthRejection>,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        switch result {
        case .success:
            Issue.record("Expected failure \(expected)", sourceLocation: sourceLocation)
        case let .failure(actual):
            #expect(actual == expected, sourceLocation: sourceLocation)
        }
    }

    @Test("a connected generation starts without inventing current speed")
    func connectedGenerationStartsUnavailable() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)

        expectSuccess(truth.beginConnectedGeneration(generation))
        let token = try #require(truth.activeContinuityToken)

        #expect(truth.activeConnectionGeneration == generation)
        #expect(truth.latestConnectionGeneration == generation)
        #expect(token.connectionGeneration == generation)
        #expect(token.segmentSequence == 1)
        #expect(truth.availability == .unavailable)
        #expect(truth.availability.currentAuthoritativeSample == nil)
    }

    @Test("only an accepted absolute sample makes active speed live")
    func authoritativeSampleMakesSpeedLive() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let measured = try sample(
            kilometersPerHour: 12.4,
            uptimeNanoseconds: 100
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let token = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(measured, attributedTo: token))

        #expect(truth.availability == .live(measured))
        #expect(truth.availability.currentAuthoritativeSample == measured)
        #expect(truth.availability.lastAcceptedSample == measured)
    }

    @Test("disconnect retains last speed without manufacturing zero")
    func disconnectDemotesLiveToRetained() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let measured = try sample(
            kilometersPerHour: 18.4,
            uptimeNanoseconds: 100
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let token = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(measured, attributedTo: token))
        expectSuccess(truth.endConnectedGeneration(generation))

        #expect(truth.activeConnectionGeneration == nil)
        #expect(truth.activeContinuityToken == nil)
        #expect(truth.availability == .retained(measured))
        #expect(truth.availability.currentAuthoritativeSample == nil)
        #expect(truth.availability.lastAcceptedSample == measured)
    }

    @Test("reconnect cannot promote retained zero before a fresh source-attributed sample")
    func reconnectRequiresFreshSpeedEvidence() throws {
        var truth = SpeedEvidenceLiveTruth()
        let first = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let second = SpeedEvidenceConnectionGeneration(rawValue: 2)
        let stoppedBeforeDisconnect = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 100
        )
        let stoppedAfterReconnect = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 200
        )

        expectSuccess(truth.beginConnectedGeneration(first))
        let firstToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(stoppedBeforeDisconnect, attributedTo: firstToken))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))
        let secondToken = try #require(truth.activeContinuityToken)

        #expect(truth.availability == .retained(stoppedBeforeDisconnect))
        #expect(truth.availability.currentAuthoritativeSample == nil)
        #expect(secondToken.connectionGeneration == second)
        #expect(secondToken != firstToken)

        expectSuccess(truth.accept(stoppedAfterReconnect, attributedTo: secondToken))
        #expect(truth.availability == .live(stoppedAfterReconnect))
    }

    @Test("delayed old-generation sample cannot become live after reconnect")
    func delayedOldGenerationFailsClosed() throws {
        var truth = SpeedEvidenceLiveTruth()
        let first = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let second = SpeedEvidenceConnectionGeneration(rawValue: 2)
        let firstSample = try sample(
            kilometersPerHour: 8,
            uptimeNanoseconds: 100
        )
        let delayedOldSample = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 200
        )

        expectSuccess(truth.beginConnectedGeneration(first))
        let firstToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(firstSample, attributedTo: firstToken))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))

        expectFailure(
            .continuityTokenMismatch,
            truth.accept(delayedOldSample, attributedTo: firstToken)
        )
        #expect(truth.availability == .retained(firstSample))
    }

    @Test("explicit evidence gap rotates source attribution before live speed can resume")
    func evidenceGapRequiresNewSourceToken() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 4)
        let beforeGap = try sample(
            kilometersPerHour: 15,
            uptimeNanoseconds: 100
        )
        let afterGap = try sample(
            kilometersPerHour: 14,
            uptimeNanoseconds: 200
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let beforeGapToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(beforeGap, attributedTo: beforeGapToken))
        expectSuccess(truth.markEvidenceGap(after: beforeGapToken))
        let afterGapToken = try #require(truth.activeContinuityToken)

        #expect(afterGapToken.connectionGeneration == generation)
        #expect(afterGapToken.segmentSequence == beforeGapToken.segmentSequence + 1)
        #expect(truth.availability == .retained(beforeGap))
        #expect(truth.availability.currentAuthoritativeSample == nil)

        expectSuccess(truth.accept(afterGap, attributedTo: afterGapToken))
        #expect(truth.availability == .live(afterGap))
    }

    @Test("queued pre-gap sample cannot resurrect live state after explicit gap")
    func queuedPreGapSampleIsRejected() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 7)
        let acceptedBeforeGap = try sample(
            kilometersPerHour: 10,
            uptimeNanoseconds: 100
        )
        let queuedBeforeGap = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 150
        )
        let acceptedAfterGap = try sample(
            kilometersPerHour: 9,
            uptimeNanoseconds: 250
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let preGapToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(acceptedBeforeGap, attributedTo: preGapToken))

        // `queuedBeforeGap` was source-attributed before this boundary but is
        // deliberately delivered only after the gap has rotated the token.
        expectSuccess(truth.markEvidenceGap(after: preGapToken))
        let postGapToken = try #require(truth.activeContinuityToken)

        expectFailure(
            .continuityTokenMismatch,
            truth.accept(queuedBeforeGap, attributedTo: preGapToken)
        )
        #expect(truth.availability == .retained(acceptedBeforeGap))

        expectSuccess(truth.accept(acceptedAfterGap, attributedTo: postGapToken))
        #expect(truth.availability == .live(acceptedAfterGap))
    }

    @Test("stale gap callback cannot demote a newer continuity segment")
    func staleGapCallbackCannotDemoteNewerSegment() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 9)
        let first = try sample(
            kilometersPerHour: 4,
            uptimeNanoseconds: 100
        )
        let newer = try sample(
            kilometersPerHour: 6,
            uptimeNanoseconds: 250
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let firstToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(first, attributedTo: firstToken))
        expectSuccess(truth.markEvidenceGap(after: firstToken))
        let newerToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(newer, attributedTo: newerToken))

        expectFailure(
            .continuityTokenMismatch,
            truth.markEvidenceGap(after: firstToken)
        )
        #expect(truth.activeContinuityToken == newerToken)
        #expect(truth.availability == .live(newer))
    }

    @Test("motion-assist estimate never becomes current authoritative speed")
    func shortHorizonEstimateIsRejected() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let estimate = try sample(
            source: .motionAssist,
            provenance: .shortHorizonEstimate,
            kilometersPerHour: 10,
            uptimeNanoseconds: 100
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let token = try #require(truth.activeContinuityToken)
        expectFailure(
            .nonAuthoritativeSample,
            truth.accept(estimate, attributedTo: token)
        )
        #expect(truth.availability == .unavailable)
    }

    @Test("receipt clock cannot move backward across or within generations")
    func receiptChronologyIsGlobalWithinProcess() throws {
        var truth = SpeedEvidenceLiveTruth()
        let first = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let second = SpeedEvidenceConnectionGeneration(rawValue: 2)
        let initial = try sample(
            kilometersPerHour: 5,
            uptimeNanoseconds: 500
        )
        let older = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 499
        )
        let equal = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 500
        )
        let newer = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 501
        )

        expectSuccess(truth.beginConnectedGeneration(first))
        let firstToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.accept(initial, attributedTo: firstToken))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))
        let secondToken = try #require(truth.activeContinuityToken)

        expectFailure(.nonMonotonicReceipt, truth.accept(older, attributedTo: secondToken))
        expectFailure(.nonMonotonicReceipt, truth.accept(equal, attributedTo: secondToken))
        #expect(truth.availability == .retained(initial))

        expectSuccess(truth.accept(newer, attributedTo: secondToken))
        #expect(truth.availability == .live(newer))
    }

    @Test("older connection generation cannot resurrect after a newer one")
    func staleConnectionGenerationIsRejected() {
        var truth = SpeedEvidenceLiveTruth()
        let first = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let second = SpeedEvidenceConnectionGeneration(rawValue: 2)

        expectSuccess(truth.beginConnectedGeneration(first))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))
        expectSuccess(truth.endConnectedGeneration(second))

        expectFailure(
            .staleConnectionGeneration,
            truth.beginConnectedGeneration(first)
        )
        #expect(truth.latestConnectionGeneration == second)
        #expect(truth.activeConnectionGeneration == nil)
        #expect(truth.activeContinuityToken == nil)
    }

    @Test("generation zero is invalid and same active generation preserves its current token")
    func generationValidationAndIdempotency() throws {
        var truth = SpeedEvidenceLiveTruth()
        let invalid = SpeedEvidenceConnectionGeneration(rawValue: 0)
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 3)

        expectFailure(
            .invalidConnectionGeneration,
            truth.beginConnectedGeneration(invalid)
        )
        expectSuccess(truth.beginConnectedGeneration(generation))
        let initialToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.beginConnectedGeneration(generation))
        #expect(truth.activeConnectionGeneration == generation)
        #expect(truth.activeContinuityToken == initialToken)
    }

    @Test("ended connection rejects samples, gaps, and duplicate end without reviving authority")
    func noActiveConnectionFailsClosed() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let measured = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 100
        )

        expectSuccess(truth.beginConnectedGeneration(generation))
        let endedToken = try #require(truth.activeContinuityToken)
        expectSuccess(truth.endConnectedGeneration(generation))

        expectFailure(
            .noActiveConnection,
            truth.accept(measured, attributedTo: endedToken)
        )
        expectFailure(
            .noActiveConnection,
            truth.markEvidenceGap(after: endedToken)
        )
        expectFailure(
            .noActiveConnection,
            truth.endConnectedGeneration(generation)
        )
        #expect(truth.availability == .unavailable)
    }
}
