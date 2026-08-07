import Testing
@testable import NembraCore

@Suite("Propulsion gauge continuity generations")
struct PropulsionGaugeContinuityGenerationTests {
    private let identity = PropulsionGaugeIdentity(vehicleID: "continuity-es80", modeKey: "sport")

    private func policy() throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: 500_000_000,
            fallSettlingDurationNanoseconds: 200_000_000,
            staleAfterNanoseconds: 2_000_000_000,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    @Test("newer continuity generation may restart sequence and uptime epochs")
    func newerGenerationStartsFreshChronologyEpoch() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 100,
            receiptSequenceNumber: 900,
            receivedAtUptimeNanoseconds: 9_000,
            continuityGeneration: 4
        ))

        try model.accept(.simulator(
            identity: identity,
            watts: 300,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            continuityGeneration: 5
        ))

        let frame = model.frame(atUptimeNanoseconds: 10, scale: nil)
        #expect(frame.availability == .live)
        #expect(frame.origin == .acceptedMeasurement)
        #expect(frame.displayWatts == 300)
        #expect(frame.latestAcceptedWatts == 300)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 1)
        #expect(frame.latestAcceptedUptimeNanoseconds == 10)

        #expect(throws: PropulsionGaugeDisplayError.staleContinuityGeneration) {
            try model.accept(.simulator(
                identity: identity,
                watts: 500,
                receiptSequenceNumber: 901,
                receivedAtUptimeNanoseconds: 9_001,
                continuityGeneration: 4
            ))
        }
    }

    @Test("same generation still requires strict receipt order and nondecreasing uptime")
    func sameGenerationKeepsStrictChronology() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 100,
            receiptSequenceNumber: 10,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 2
        ))

        #expect(throws: PropulsionGaugeDisplayError.nonMonotonicMeasurement) {
            try model.accept(.simulator(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 11,
                receivedAtUptimeNanoseconds: 99,
                continuityGeneration: 2
            ))
        }

        #expect(throws: PropulsionGaugeDisplayError.nonIncreasingReceiptSequence) {
            try model.accept(.simulator(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 11,
                receivedAtUptimeNanoseconds: 100,
                continuityGeneration: 2
            ))
        }

        try model.accept(.simulator(
            identity: identity,
            watts: 250,
            receiptSequenceNumber: 12,
            receivedAtUptimeNanoseconds: 100,
            continuityGeneration: 2
        ))

        let frame = model.frame(atUptimeNanoseconds: 100, scale: nil)
        #expect(frame.latestAcceptedWatts == 250)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 12)
    }

    @Test("explicit unavailability retires the old generation until a newer one arrives")
    func unavailableRetiresOldGeneration() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())

        try model.accept(.simulator(
            identity: identity,
            watts: 420,
            receiptSequenceNumber: 50,
            receivedAtUptimeNanoseconds: 500,
            continuityGeneration: 7
        ))
        model.markUnavailable()

        #expect(throws: PropulsionGaugeDisplayError.retiredContinuityGeneration) {
            try model.accept(.simulator(
                identity: identity,
                watts: 430,
                receiptSequenceNumber: 51,
                receivedAtUptimeNanoseconds: 501,
                continuityGeneration: 7
            ))
        }

        let unavailable = model.frame(atUptimeNanoseconds: 600, scale: nil)
        #expect(unavailable.availability == .unavailable)
        #expect(unavailable.origin == .unavailable)
        #expect(unavailable.displayWatts == nil)
        #expect(unavailable.latestAcceptedWatts == 420)

        // A genuinely newer source generation may restart both ordering clocks.
        try model.accept(.simulator(
            identity: identity,
            watts: 200,
            receiptSequenceNumber: 1,
            receivedAtUptimeNanoseconds: 10,
            continuityGeneration: 8
        ))

        let resumed = model.frame(atUptimeNanoseconds: 10, scale: nil)
        #expect(resumed.availability == .live)
        #expect(resumed.origin == .acceptedMeasurement)
        #expect(resumed.displayWatts == 200)
        #expect(resumed.latestAcceptedReceiptSequenceNumber == 1)
        #expect(resumed.latestAcceptedUptimeNanoseconds == 10)
    }
}
