import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence snapshot accumulator")
struct BatteryEvidenceSnapshotAccumulatorTests {
    private func observation(
        field: BatteryEvidenceField,
        uptime: UInt64,
        numericValue: Double = 50,
        continuity: BatteryEvidenceContinuity = .continuous,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        date: TimeInterval = 1_000
    ) throws -> BatteryEvidenceObservation {
        let value: BatterySemanticValue
        switch field {
        case .stateOfChargePercent:
            value = try BatterySemanticValue.stateOfChargePercent(numericValue)
        case .voltageVolts:
            value = try BatterySemanticValue.voltageVolts(numericValue)
        case .currentAmps:
            value = try BatterySemanticValue.currentAmps(numericValue)
        case .powerWatts:
            value = try BatterySemanticValue.powerWatts(numericValue)
        case .chargingState:
            value = try BatterySemanticValue.chargingState(numericValue != 0)
        }

        return try BatteryEvidenceObservation(
            value: value,
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: date),
            continuity: continuity
        )
    }

    @Test("same callback can populate multiple current fields coherently")
    func sameUptimeMultipleFieldsBuildSnapshot() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()

        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 10, numericValue: 72))
        try accumulator.ingest(try observation(field: .voltageVolts, uptime: 10, numericValue: 40.1))
        try accumulator.ingest(try observation(field: .currentAmps, uptime: 10, numericValue: 4.2))

        let snapshot = accumulator.currentSnapshot
        #expect(snapshot.observationsByField.count == 3)
        #expect(snapshot[.stateOfChargePercent]?.value.numericValue == 72)
        #expect(snapshot[.voltageVolts]?.value.numericValue == 40.1)
        #expect(snapshot[.currentAmps]?.value.numericValue == 4.2)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 10)
    }

    @Test("newer evidence replaces only its own field")
    func newerFieldEvidenceReplacesPreviousValue() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()

        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 10, numericValue: 72))
        try accumulator.ingest(try observation(field: .voltageVolts, uptime: 10, numericValue: 40.1))
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 11, numericValue: 71))

        let snapshot = accumulator.currentSnapshot
        #expect(snapshot[.stateOfChargePercent]?.value.numericValue == 71)
        #expect(snapshot[.voltageVolts]?.value.numericValue == 40.1)
        #expect(snapshot[.stateOfChargePercent]?.receivedAtUptimeNanoseconds == 11)
    }

    @Test("exact duplicate evidence is idempotent")
    func exactDuplicateIsIdempotent() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        let evidence = try observation(field: .stateOfChargePercent, uptime: 20, numericValue: 65)

        try accumulator.ingest(evidence)
        let before = accumulator
        try accumulator.ingest(evidence)

        #expect(accumulator == before)
    }

    @Test("conflicting same-field same-uptime evidence fails atomically")
    func conflictingSameUptimeFieldFailsClosed() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 30, numericValue: 65))
        let before = accumulator

        var captured: BatteryEvidenceSnapshotError?
        do {
            try accumulator.ingest(
                try observation(field: .stateOfChargePercent, uptime: 30, numericValue: 64)
            )
        } catch let error as BatteryEvidenceSnapshotError {
            captured = error
        }

        #expect(captured == .conflictingSameUptimeFieldEvidence)
        #expect(accumulator == before)
    }

    @Test("known gap clears current fields before post-gap evidence arrives")
    func markGapClearsCurrentSnapshot() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 100, numericValue: 55))
        try accumulator.ingest(try observation(field: .voltageVolts, uptime: 100, numericValue: 39.2))

        accumulator.markUnobservedInterval()

        #expect(accumulator.currentSnapshot.isEmpty)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == nil)
        #expect(accumulator.requiresContinuityBoundary)
    }

    @Test("continuous evidence after a known gap is rejected and remains empty")
    func markedGapRejectsSilentBridge() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 100, numericValue: 55))
        accumulator.markUnobservedInterval()

        var captured: BatteryEvidenceSnapshotError?
        do {
            try accumulator.ingest(
                try observation(field: .stateOfChargePercent, uptime: 101, numericValue: 54)
            )
        } catch let error as BatteryEvidenceSnapshotError {
            captured = error
        }

        #expect(captured == .stream(.missingContinuityBoundary))
        #expect(accumulator.currentSnapshot.isEmpty)
        #expect(accumulator.requiresContinuityBoundary)
    }

    @Test("post-gap boundary starts a fresh snapshot and cannot mix stale fields")
    func postGapBoundaryStartsFreshSegment() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 9_000, numericValue: 55))
        try accumulator.ingest(try observation(field: .voltageVolts, uptime: 9_000, numericValue: 39.2))
        accumulator.markUnobservedInterval()

        try accumulator.ingest(
            try observation(
                field: .stateOfChargePercent,
                uptime: 4,
                numericValue: 54,
                continuity: .afterUnobservedInterval
            )
        )

        let snapshot = accumulator.currentSnapshot
        #expect(snapshot.observationsByField.count == 1)
        #expect(snapshot[.stateOfChargePercent]?.value.numericValue == 54)
        #expect(snapshot[.voltageVolts] == nil)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 4)
        #expect(!accumulator.requiresContinuityBoundary)
    }

    @Test("spontaneous conservative boundary also drops prior fields")
    func explicitBoundaryDropsPriorSegment() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .currentAmps, uptime: 700, numericValue: 3.5))
        try accumulator.ingest(
            try observation(
                field: .stateOfChargePercent,
                uptime: 2,
                numericValue: 60,
                continuity: .afterUnobservedInterval
            )
        )

        #expect(accumulator.currentSnapshot[.currentAmps] == nil)
        #expect(accumulator.currentSnapshot[.stateOfChargePercent]?.value.numericValue == 60)
    }

    @Test("backwards stream evidence cannot mutate the current snapshot")
    func backwardsEvidenceFailsAtomically() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(try observation(field: .stateOfChargePercent, uptime: 50, numericValue: 70))
        let before = accumulator

        var captured: BatteryEvidenceSnapshotError?
        do {
            try accumulator.ingest(try observation(field: .voltageVolts, uptime: 49, numericValue: 40))
        } catch let error as BatteryEvidenceSnapshotError {
            captured = error
        }

        #expect(captured == .stream(.nonMonotonicUptime))
        #expect(accumulator == before)
    }

    @Test("snapshot retention never promotes stock-app correlation evidence")
    func snapshotDoesNotPromoteTruthRole() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        try accumulator.ingest(
            try observation(
                field: .voltageVolts,
                uptime: 10,
                numericValue: 40,
                role: .stockAppCorrelationAnchor
            )
        )

        let retained = try #require(accumulator.currentSnapshot[.voltageVolts])
        #expect(retained.role == .stockAppCorrelationAnchor)
        #expect(!retained.isVerifiedElectricalTelemetry)
    }
}
