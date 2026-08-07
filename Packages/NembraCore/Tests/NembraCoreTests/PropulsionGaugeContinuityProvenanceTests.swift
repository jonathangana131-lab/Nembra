import Testing
@testable import NembraCore

@Suite("Propulsion gauge continuity provenance")
struct PropulsionGaugeContinuityProvenanceTests {
    private func identity() throws -> PropulsionGaugeIdentity {
        try PropulsionGaugeIdentity(vehicleID: "es80-continuity", modeKey: "drive")
    }

    private func model(
        identity: PropulsionGaugeIdentity
    ) throws -> PropulsionGaugeDisplayModel {
        PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: try PropulsionGaugeAnimationPolicy(
                riseSettlingDurationNanoseconds: 500_000_000,
                fallSettlingDurationNanoseconds: 250_000_000,
                acceptedPeakHoldNanoseconds: 750_000_000
            ),
            freshnessPolicy: try PropulsionGaugeFreshnessPolicy(
                staleAfterNanoseconds: 2_000_000_000
            )
        )
    }

    private func sample(
        identity: PropulsionGaugeIdentity,
        generation: UInt64,
        watts: Double = 640,
        receipt: UInt64 = 7,
        uptime: UInt64 = 1_000_000_000
    ) throws -> PropulsionPowerSample {
        try .simulator(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receipt,
            receivedAtUptimeNanoseconds: uptime,
            continuityGeneration: generation
        )
    }

    @Test("canonical frames stay distinguishable when a newer generation restarts receipt and uptime")
    func frameCarriesRestartedGeneration() throws {
        let sourceIdentity = try identity()
        var displayModel = try model(identity: sourceIdentity)

        try displayModel.accept(sample(identity: sourceIdentity, generation: 1))
        let first = displayModel.frame(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )

        // A new source generation may legitimately restart both chronology fields.
        try displayModel.accept(sample(identity: sourceIdentity, generation: 2))
        let second = displayModel.frame(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )

        #expect(first.identity == sourceIdentity)
        #expect(second.identity == sourceIdentity)
        #expect(first.latestAcceptedWatts == second.latestAcceptedWatts)
        #expect(first.latestAcceptedReceiptSequenceNumber == second.latestAcceptedReceiptSequenceNumber)
        #expect(first.latestAcceptedUptimeNanoseconds == second.latestAcceptedUptimeNanoseconds)
        #expect(first.latestAuthority == second.latestAuthority)
        #expect(first.latestAcceptedContinuityGeneration == 1)
        #expect(second.latestAcceptedContinuityGeneration == 2)
        #expect(first != second)
    }

    @Test("cockpit measurements preserve generation when all other accepted metadata repeats")
    func cockpitMeasurementCarriesRestartedGeneration() throws {
        let sourceIdentity = try identity()
        var displayModel = try model(identity: sourceIdentity)

        try displayModel.accept(sample(identity: sourceIdentity, generation: 4))
        let first = displayModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )

        try displayModel.accept(sample(identity: sourceIdentity, generation: 5))
        let second = displayModel.cockpitSnapshot(
            atUptimeNanoseconds: 1_000_000_000,
            scale: nil
        )

        guard case let .live(firstMeasurement) = first.measurement,
              case let .live(secondMeasurement) = second.measurement else {
            #expect(Bool(false))
            return
        }

        #expect(firstMeasurement.identity == sourceIdentity)
        #expect(secondMeasurement.identity == sourceIdentity)
        #expect(firstMeasurement.watts == secondMeasurement.watts)
        #expect(firstMeasurement.receiptSequenceNumber == secondMeasurement.receiptSequenceNumber)
        #expect(firstMeasurement.receivedAtUptimeNanoseconds == secondMeasurement.receivedAtUptimeNanoseconds)
        #expect(firstMeasurement.authority == secondMeasurement.authority)
        #expect(firstMeasurement.continuityGeneration == 4)
        #expect(secondMeasurement.continuityGeneration == 5)
        #expect(firstMeasurement != secondMeasurement)
        #expect(first != second)
    }

    @Test("retained frame preserves accepted generation while cockpit remains explicitly retained")
    func retainedFrameAndCockpitKeepGeneration() throws {
        let sourceIdentity = try identity()
        var displayModel = try model(identity: sourceIdentity)
        try displayModel.accept(
            sample(
                identity: sourceIdentity,
                generation: 9,
                watts: 510,
                receipt: 33,
                uptime: 2_000_000_000
            )
        )

        let frame = displayModel.frame(
            atUptimeNanoseconds: 4_000_000_001,
            scale: nil
        )
        let cockpit = displayModel.cockpitSnapshot(
            atUptimeNanoseconds: 4_000_000_001,
            scale: nil
        )

        #expect(frame.identity == sourceIdentity)
        #expect(frame.availability == .retained)
        #expect(frame.latestAcceptedContinuityGeneration == 9)

        guard case let .retained(measurement) = cockpit.measurement else {
            #expect(Bool(false))
            return
        }
        #expect(measurement.identity == sourceIdentity)
        #expect(measurement.continuityGeneration == 9)
        #expect(measurement.watts == 510)
    }

    @Test("unmeasured frame still carries model identity without inventing generation")
    func unavailableFrameKeepsIdentityWithoutGeneration() throws {
        let sourceIdentity = try identity()
        let displayModel = try model(identity: sourceIdentity)

        let frame = displayModel.frame(
            atUptimeNanoseconds: 123,
            scale: nil
        )

        #expect(frame.identity == sourceIdentity)
        #expect(frame.availability == .unavailable)
        #expect(frame.latestAcceptedContinuityGeneration == nil)
        #expect(frame.latestAcceptedWatts == nil)
    }
}