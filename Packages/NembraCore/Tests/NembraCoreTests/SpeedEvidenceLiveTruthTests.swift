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
    func connectedGenerationStartsUnavailable() {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)

        expectSuccess(truth.beginConnectedGeneration(generation))

        #expect(truth.activeConnectionGeneration == generation)
        #expect(truth.latestConnectionGeneration == generation)
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
        expectSuccess(truth.accept(measured, in: generation))

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
        expectSuccess(truth.accept(measured, in: generation))
        expectSuccess(truth.endConnectedGeneration(generation))

        #expect(truth.activeConnectionGeneration == nil)
        #expect(truth.availability == .retained(measured))
        #expect(truth.availability.currentAuthoritativeSample == nil)
        #expect(truth.availability.lastAcceptedSample == measured)
    }

    @Test("reconnect cannot promote retained zero before a fresh sample")
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
        expectSuccess(truth.accept(stoppedBeforeDisconnect, in: first))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))

        #expect(truth.availability == .retained(stoppedBeforeDisconnect))
        #expect(truth.availability.currentAuthoritativeSample == nil)

        expectSuccess(truth.accept(stoppedAfterReconnect, in: second))
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
        expectSuccess(truth.accept(firstSample, in: first))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))

        expectFailure(
            .connectionGenerationMismatch,
            truth.accept(delayedOldSample, in: first)
        )
        #expect(truth.availability == .retained(firstSample))
    }

    @Test("explicit evidence gap demotes live speed until a newer sample arrives")
    func evidenceGapRequiresNewSample() throws {
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
        expectSuccess(truth.accept(beforeGap, in: generation))
        expectSuccess(truth.markEvidenceGap(in: generation))

        #expect(truth.availability == .retained(beforeGap))
        #expect(truth.availability.currentAuthoritativeSample == nil)

        expectSuccess(truth.accept(afterGap, in: generation))
        #expect(truth.availability == .live(afterGap))
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
        expectFailure(
            .nonAuthoritativeSample,
            truth.accept(estimate, in: generation)
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
        expectSuccess(truth.accept(initial, in: first))
        expectSuccess(truth.endConnectedGeneration(first))
        expectSuccess(truth.beginConnectedGeneration(second))

        expectFailure(.nonMonotonicReceipt, truth.accept(older, in: second))
        expectFailure(.nonMonotonicReceipt, truth.accept(equal, in: second))
        #expect(truth.availability == .retained(initial))

        expectSuccess(truth.accept(newer, in: second))
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
    }

    @Test("generation zero is invalid and same active generation is idempotent")
    func generationValidationAndIdempotency() {
        var truth = SpeedEvidenceLiveTruth()
        let invalid = SpeedEvidenceConnectionGeneration(rawValue: 0)
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 3)

        expectFailure(
            .invalidConnectionGeneration,
            truth.beginConnectedGeneration(invalid)
        )
        expectSuccess(truth.beginConnectedGeneration(generation))
        expectSuccess(truth.beginConnectedGeneration(generation))
        #expect(truth.activeConnectionGeneration == generation)
    }

    @Test("samples without an active connection cannot become live")
    func noActiveConnectionFailsClosed() throws {
        var truth = SpeedEvidenceLiveTruth()
        let generation = SpeedEvidenceConnectionGeneration(rawValue: 1)
        let measured = try sample(
            kilometersPerHour: 0,
            uptimeNanoseconds: 100
        )

        expectFailure(.noActiveConnection, truth.accept(measured, in: generation))
        expectFailure(.noActiveConnection, truth.markEvidenceGap(in: generation))
        expectFailure(.noActiveConnection, truth.endConnectedGeneration(generation))
        #expect(truth.availability == .unavailable)
    }
}
