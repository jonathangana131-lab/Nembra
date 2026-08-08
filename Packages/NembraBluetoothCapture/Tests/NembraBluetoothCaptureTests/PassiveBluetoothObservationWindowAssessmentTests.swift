import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive Bluetooth observation window assessment")
struct PassiveBluetoothObservationWindowAssessmentTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private func interruptionRecord(
        sequenceNumber: UInt64,
        uptime: UInt64
    ) throws -> PassiveBluetoothCaptureRecord {
        PassiveBluetoothCaptureRecord(
            sequenceNumber: sequenceNumber,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: TimeInterval(sequenceNumber)),
            event: .interruption(
                try PassiveBluetoothCaptureInterruption(reason: "test evidence")
            )
        )
    }

    private func boundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        watermark: UInt64,
        uptime: UInt64,
        wallClock: TimeInterval = 0
    ) -> PassiveBluetoothObservationBoundary {
        PassiveBluetoothObservationBoundary(
            kind: kind,
            recordSequenceWatermark: watermark,
            observedAtUptimeNanoseconds: uptime,
            observedAtDate: Date(timeIntervalSince1970: wallClock)
        )
    }

    @Test("exact quiet 60-second window meets an explicit 60-second policy")
    func exactQuietMinuteMeetsPolicy() throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000365")!
        let readyUptime: UInt64 = 10_000_000_000
        var session = try PassiveBluetoothCaptureSession(
            id: sessionID,
            vehicleIdentity: es80,
            startedAt: .now
        )
        try session.append(interruptionRecord(sequenceNumber: 10, uptime: readyUptime - 1))
        try session.appendObservationBoundary(
            boundary(
                .finiteAcquisitionReady,
                watermark: 10,
                uptime: readyUptime,
                wallClock: 100
            )
        )
        try session.appendObservationBoundary(
            boundary(
                .observationHorizon,
                watermark: 10,
                uptime: readyUptime + 60_000_000_000,
                wallClock: 160
            )
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.captureSessionID == sessionID)
        #expect(report.vehicleIdentity == es80)
        #expect(report.disposition == .meetsMinimumObservedDuration)
        #expect(report.meetsMinimumObservedDuration)
        #expect(report.observedDurationNanoseconds == 60_000_000_000)
        #expect(report.minimumObservedDurationNanoseconds == 60_000_000_000)
        #expect(report.finiteAcquisitionReadyBoundaryCount == 1)
        #expect(report.observationHorizonBoundaryCount == 1)
        #expect(report.rawEvidenceAdvancedDuringWindow == false)
        #expect(report.finiteAcquisitionReadyBoundary?.recordSequenceWatermark == 10)
        #expect(report.observationHorizonBoundary?.recordSequenceWatermark == 10)
    }

    @Test("one nanosecond short remains below the explicit policy")
    func oneNanosecondShortFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            boundary(.finiteAcquisitionReady, watermark: 0, uptime: 1_000)
        )
        try session.appendObservationBoundary(
            boundary(
                .observationHorizon,
                watermark: 0,
                uptime: 60_000_000_999
            )
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.disposition == .observedDurationTooShort)
        #expect(!report.meetsMinimumObservedDuration)
        #expect(report.observedDurationNanoseconds == 59_999_999_999)
    }

    @Test("missing finite-acquisition readiness never inherits duration from the horizon")
    func missingReadyFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            boundary(.observationHorizon, watermark: 0, uptime: 90_000_000_000)
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.captureSessionID == session.id)
        #expect(report.vehicleIdentity == session.vehicleIdentity)
        #expect(report.disposition == .missingFiniteAcquisitionReadyBoundary)
        #expect(report.observedDurationNanoseconds == nil)
        #expect(report.finiteAcquisitionReadyBoundary == nil)
        #expect(report.observationHorizonBoundary != nil)
        #expect(report.rawEvidenceAdvancedDuringWindow == nil)
    }

    @Test("ready evidence without an immutable horizon is incomplete")
    func missingHorizonFailsClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            boundary(.finiteAcquisitionReady, watermark: 0, uptime: 5_000)
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.disposition == .missingObservationHorizonBoundary)
        #expect(report.observedDurationNanoseconds == nil)
        #expect(report.finiteAcquisitionReadyBoundary != nil)
        #expect(report.observationHorizonBoundary == nil)
        #expect(report.rawEvidenceAdvancedDuringWindow == nil)
    }

    @Test("multiple ready boundaries are ambiguous rather than silently selecting one")
    func repeatedReadyBoundariesFailClosed() throws {
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            boundary(.finiteAcquisitionReady, watermark: 0, uptime: 1_000)
        )
        try session.appendObservationBoundary(
            boundary(.finiteAcquisitionReady, watermark: 0, uptime: 2_000)
        )
        try session.appendObservationBoundary(
            boundary(.observationHorizon, watermark: 0, uptime: 90_000_000_000)
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.disposition == .ambiguousFiniteAcquisitionReadyBoundary)
        #expect(report.finiteAcquisitionReadyBoundaryCount == 2)
        #expect(report.finiteAcquisitionReadyBoundary == nil)
        #expect(report.observedDurationNanoseconds == nil)
        #expect(!report.meetsMinimumObservedDuration)
    }

    @Test("wall-clock reversal cannot erase monotonic observed duration")
    func wallClockIsNotDurationAuthority() throws {
        let readyUptime: UInt64 = 3_000
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.appendObservationBoundary(
            boundary(
                .finiteAcquisitionReady,
                watermark: 0,
                uptime: readyUptime,
                wallClock: 500
            )
        )
        try session.appendObservationBoundary(
            boundary(
                .observationHorizon,
                watermark: 0,
                uptime: readyUptime + 60_000_000_000,
                wallClock: 100
            )
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.disposition == .meetsMinimumObservedDuration)
        #expect(report.observedDurationNanoseconds == 60_000_000_000)
    }

    @Test("raw callbacks may advance during a qualifying observation window")
    func advancingRawEvidenceRemainsDescriptive() throws {
        let readyUptime: UInt64 = 10_000
        var session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)
        try session.append(interruptionRecord(sequenceNumber: 7, uptime: readyUptime - 1))
        try session.appendObservationBoundary(
            boundary(.finiteAcquisitionReady, watermark: 7, uptime: readyUptime)
        )
        try session.append(
            interruptionRecord(
                sequenceNumber: 42,
                uptime: readyUptime + 30_000_000_000
            )
        )
        try session.appendObservationBoundary(
            boundary(
                .observationHorizon,
                watermark: 42,
                uptime: readyUptime + 60_000_000_000
            )
        )

        let report = try PassiveBluetoothObservationWindowAssessment.assess(
            session,
            minimumObservedDurationNanoseconds: 60_000_000_000
        )

        #expect(report.disposition == .meetsMinimumObservedDuration)
        #expect(report.rawEvidenceAdvancedDuringWindow == true)
        #expect(report.finiteAcquisitionReadyBoundary?.recordSequenceWatermark == 7)
        #expect(report.observationHorizonBoundary?.recordSequenceWatermark == 42)
    }

    @Test("zero-duration policy is rejected instead of making every horizon ready")
    func zeroMinimumPolicyIsInvalid() throws {
        let session = try PassiveBluetoothCaptureSession(vehicleIdentity: es80, startedAt: .now)

        #expect(
            throws: PassiveBluetoothObservationWindowAssessmentError
                .invalidMinimumObservedDurationNanoseconds
        ) {
            _ = try PassiveBluetoothObservationWindowAssessment.assess(
                session,
                minimumObservedDurationNanoseconds: 0
            )
        }
    }
}
