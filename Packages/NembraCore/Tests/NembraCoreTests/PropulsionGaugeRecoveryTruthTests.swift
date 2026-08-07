import Foundation
import Testing
@testable import NembraCore

// Compatibility only for the recovered predecessor tests. Production/package
// clients must supply source-owned receipt order to the sealed verified factory.
extension PropulsionPowerSample {
    static func verifiedVehicleMeasurement(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) throws -> Self {
        try .verifiedVehicleMeasurement(
            identity: identity,
            watts: watts,
            receiptSequenceNumber: receivedAtUptimeNanoseconds,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration
        )
    }
}

@Suite("Propulsion gauge recovery truth")
struct PropulsionGaugeRecoveryTruthTests {
    private let identity = PropulsionGaugeIdentity(vehicleID: "recovery-es80", modeKey: "sport")

    private func policy(
        rise: UInt64 = 1_000_000_000,
        fall: UInt64 = 250_000_000,
        stale: UInt64 = 2_000_000_000
    ) throws -> PropulsionGaugeMotionPolicy {
        try PropulsionGaugeMotionPolicy(
            riseSettlingDurationNanoseconds: rise,
            fallSettlingDurationNanoseconds: fall,
            staleAfterNanoseconds: stale,
            acceptedPeakHoldNanoseconds: 500_000_000
        )
    }

    @Test("authority-bearing samples and scales reject structurally empty identity")
    func emptyIdentityFailsClosed() {
        let emptyVehicle = PropulsionGaugeIdentity(vehicleID: "  \n")
        #expect(throws: PropulsionPowerSampleError.invalidIdentity) {
            try PropulsionPowerSample.simulator(
                identity: emptyVehicle,
                watts: 100,
                receivedAtUptimeNanoseconds: 1,
                continuityGeneration: 1
            )
        }

        let emptyMode = PropulsionGaugeIdentity(vehicleID: "es80", modeKey: " \t")
        #expect(throws: PropulsionGaugeScaleError.invalidIdentity) {
            try PropulsionGaugeScale.simulator(identity: emptyMode, ceilingWatts: 500)
        }

        #expect(throws: PropulsionPowerSampleError.invalidIdentity) {
            try PropulsionPowerSample.verifiedVehicleMeasurement(
                identity: emptyVehicle,
                watts: 100,
                receiptSequenceNumber: 1,
                receivedAtUptimeNanoseconds: 1,
                continuityGeneration: 1
            )
        }
    }

    @Test("power release cannot settle slower than application")
    func fallMustBeAtLeastAsResponsiveAsRise() throws {
        #expect(throws: PropulsionGaugeMotionPolicyError.fallResponseSlowerThanRise) {
            try PropulsionGaugeMotionPolicy(
                riseSettlingDurationNanoseconds: 200,
                fallSettlingDurationNanoseconds: 201,
                staleAfterNanoseconds: 1_000,
                acceptedPeakHoldNanoseconds: 100
            )
        }

        let equal = try policy(rise: 200, fall: 200)
        #expect(equal.fallSettlingDurationNanoseconds == equal.riseSettlingDurationNanoseconds)

        let reduceMotion = try policy(rise: 0, fall: 0)
        #expect(reduceMotion.riseSettlingDurationNanoseconds == 0)
        #expect(reduceMotion.fallSettlingDurationNanoseconds == 0)
    }

    @Test("render clock cannot expose a measurement before its receipt")
    func renderClockRollbackFailsClosed() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(.simulator(
            identity: identity,
            watts: 420,
            receiptSequenceNumber: 7,
            receivedAtUptimeNanoseconds: 10_000,
            continuityGeneration: 1
        ))

        let frame = model.frame(atUptimeNanoseconds: 9_999, scale: nil)
        #expect(frame.availability == .unavailable)
        #expect(frame.origin == .invalidRenderClock)
        #expect(frame.displayWatts == nil)
        #expect(frame.latestAcceptedWatts == nil)
        #expect(frame.latestAcceptedReceiptSequenceNumber == nil)
        #expect(frame.latestAcceptedUptimeNanoseconds == nil)
        #expect(frame.latestAuthority == nil)
    }

    @Test("same uptime tick is valid when source receipt sequence advances")
    func sameTickReceiptOrderIsPreserved() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(.simulator(
            identity: identity,
            watts: 100,
            receiptSequenceNumber: 10,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))
        try model.accept(.simulator(
            identity: identity,
            watts: 300,
            receiptSequenceNumber: 11,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        let frame = model.frame(atUptimeNanoseconds: 1_000, scale: nil)
        #expect(frame.latestAcceptedWatts == 300)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 11)
        #expect(frame.latestAcceptedUptimeNanoseconds == 1_000)
    }

    @Test("receipt replay and backwards uptime fail closed without rewriting chronology")
    func receiptChronologyFailsClosed() throws {
        var model = PropulsionGaugeDisplayModel(identity: identity, policy: try policy())
        try model.accept(.simulator(
            identity: identity,
            watts: 100,
            receiptSequenceNumber: 10,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))

        #expect(throws: PropulsionGaugeDisplayError.nonIncreasingReceiptSequence) {
            try model.accept(.simulator(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 10,
                receivedAtUptimeNanoseconds: 1_000,
                continuityGeneration: 1
            ))
        }

        #expect(throws: PropulsionGaugeDisplayError.nonMonotonicMeasurement) {
            try model.accept(.simulator(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 11,
                receivedAtUptimeNanoseconds: 999,
                continuityGeneration: 1
            ))
        }

        // Sequence 11 was a real newer callback identity even though its uptime
        // metadata failed. It cannot be rewritten and re-entered afterward.
        #expect(throws: PropulsionGaugeDisplayError.nonIncreasingReceiptSequence) {
            try model.accept(.simulator(
                identity: identity,
                watts: 200,
                receiptSequenceNumber: 11,
                receivedAtUptimeNanoseconds: 1_000,
                continuityGeneration: 1
            ))
        }

        try model.accept(.simulator(
            identity: identity,
            watts: 250,
            receiptSequenceNumber: 12,
            receivedAtUptimeNanoseconds: 1_000,
            continuityGeneration: 1
        ))
        let frame = model.frame(atUptimeNanoseconds: 1_000, scale: nil)
        #expect(frame.latestAcceptedWatts == 250)
        #expect(frame.latestAcceptedReceiptSequenceNumber == 12)
    }

    @Test("canonical simulator envelope maps without gaining verified authority")
    func simulatorEnvelopeMapsToSimulatorScale() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(
            vehicleIdentityKey: "sim-es80",
            confirmedModeKey: "sport"
        )
        let calibration = ObservedPowerEnvelopeCalibration(
            scope: scope,
            evidenceAuthority: .simulatorQA,
            learnedObservedCeilingWatts: 500,
            learnedGaugeScaleWatts: 525,
            learningSampleCount: 20,
            upperBandSupportCount: 5
        )

        let scale = try PropulsionGaugeScale.observedEnvelope(calibration)
        #expect(scale.identity == PropulsionGaugeIdentity(vehicleID: "sim-es80", modeKey: "sport"))
        #expect(scale.ceilingWatts == 525)
        #expect(scale.origin == .simulator)
    }

    @Test("canonical verified envelope maps through the sealed verified scale boundary")
    func verifiedEnvelopeMapsToVerifiedScale() throws {
        let scope = try ObservedPowerEnvelopeScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "physical-es80-key",
            confirmedModeKey: "sport"
        )
        let calibration = ObservedPowerEnvelopeCalibration(
            scope: scope,
            evidenceAuthority: .verifiedVehicleMeasurement,
            learnedObservedCeilingWatts: 500,
            learnedGaugeScaleWatts: 525,
            learningSampleCount: 20,
            upperBandSupportCount: 5
        )

        let scale = try PropulsionGaugeScale.observedEnvelope(calibration)
        #expect(scale.identity == PropulsionGaugeIdentity(vehicleID: "physical-es80-key", modeKey: "sport"))
        #expect(scale.ceilingWatts == 525)
        #expect(scale.origin == .verifiedObservedEnvelope)
    }

    @Test("mismatched envelope authorities cannot be upgraded by presentation")
    func mismatchedEnvelopeAuthoritiesFailClosed() throws {
        let scope = try ObservedPowerEnvelopeScope.simulatorQA(vehicleIdentityKey: "sim-es80")
        let calibration = ObservedPowerEnvelopeCalibration(
            scope: scope,
            evidenceAuthority: .verifiedVehicleMeasurement,
            learnedObservedCeilingWatts: 500,
            learnedGaugeScaleWatts: 525,
            learningSampleCount: 20,
            upperBandSupportCount: 5
        )

        #expect(throws: PropulsionGaugeScaleError.envelopeAuthorityMismatch) {
            try PropulsionGaugeScale.observedEnvelope(calibration)
        }
    }
}
