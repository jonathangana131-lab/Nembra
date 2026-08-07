import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence snapshot replay regressions")
struct BatteryEvidenceSnapshotReplayRegressionTests {
    private func observation(
        field: BatteryEvidenceField,
        uptime: UInt64,
        numericValue: Double,
        continuity: BatteryEvidenceContinuity = .continuous
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
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1_000),
            continuity: continuity
        )
    }

    @Test("replaying an old accepted boundary cannot rewind the ordering baseline")
    func oldBoundaryReplayIsFullyIdempotent() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        let boundary = try observation(
            field: .stateOfChargePercent,
            uptime: 4,
            numericValue: 54,
            continuity: .afterUnobservedInterval
        )

        try accumulator.ingest(boundary)
        try accumulator.ingest(
            try observation(field: .currentAmps, uptime: 5, numericValue: 3.0)
        )
        let beforeReplay = accumulator

        try accumulator.ingest(boundary)

        #expect(accumulator == beforeReplay)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 5)
        #expect(accumulator.currentSnapshot[.stateOfChargePercent] == boundary)
    }

    @Test("boundary replay keeps lower continuous evidence rejected")
    func oldBoundaryReplayPreservesOrderingEnforcement() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        let boundary = try observation(
            field: .stateOfChargePercent,
            uptime: 4,
            numericValue: 54,
            continuity: .afterUnobservedInterval
        )

        try accumulator.ingest(boundary)
        try accumulator.ingest(
            try observation(field: .currentAmps, uptime: 5, numericValue: 3.0)
        )
        try accumulator.ingest(boundary)
        let beforeRejectedEvidence = accumulator

        var captured: BatteryEvidenceSnapshotError?
        do {
            try accumulator.ingest(
                try observation(field: .voltageVolts, uptime: 4, numericValue: 39.6)
            )
        } catch let error as BatteryEvidenceSnapshotError {
            captured = error
        }

        #expect(captured == .stream(.nonMonotonicUptime))
        #expect(accumulator == beforeRejectedEvidence)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 5)
    }

    @Test("replaying old ordinary evidence is also globally idempotent")
    func oldContinuousReplayIsFullyIdempotent() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        let soc = try observation(
            field: .stateOfChargePercent,
            uptime: 10,
            numericValue: 70
        )

        try accumulator.ingest(soc)
        try accumulator.ingest(
            try observation(field: .voltageVolts, uptime: 11, numericValue: 40.0)
        )
        let beforeReplay = accumulator

        try accumulator.ingest(soc)

        #expect(accumulator == beforeReplay)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 11)
    }

    @Test("ordinary replay keeps lower continuous evidence rejected")
    func oldContinuousReplayPreservesOrderingEnforcement() throws {
        var accumulator = BatteryEvidenceSnapshotAccumulator()
        let soc = try observation(
            field: .stateOfChargePercent,
            uptime: 10,
            numericValue: 70
        )

        try accumulator.ingest(soc)
        try accumulator.ingest(
            try observation(field: .voltageVolts, uptime: 11, numericValue: 40.0)
        )
        try accumulator.ingest(soc)
        let beforeRejectedEvidence = accumulator

        var captured: BatteryEvidenceSnapshotError?
        do {
            try accumulator.ingest(
                try observation(field: .currentAmps, uptime: 10, numericValue: 2.5)
            )
        } catch let error as BatteryEvidenceSnapshotError {
            captured = error
        }

        #expect(captured == .stream(.nonMonotonicUptime))
        #expect(accumulator == beforeRejectedEvidence)
        #expect(accumulator.lastAcceptedUptimeNanoseconds == 11)
    }
}
