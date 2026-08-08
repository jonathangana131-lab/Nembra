import Foundation
import Testing
@testable import NembraCore

@Suite("Passive Bluetooth observation-window duration assessment")
struct PassiveBluetoothObservationWindowDurationAssessmentTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )
    private let deferredMaxshot = VehicleIdentity(
        manufacturer: "MAXSHOT",
        model: "V1S Pro",
        displayName: "MAXSHOT V1S Pro",
        protocolFamily: "Deferred / unverified"
    )
    private let defaultSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000363")!

    @Test("quiet exact-minimum interval is sufficient without inventing BLE events")
    func quietExactMinimumIsSufficient() throws {
        let session = try makeSession(
            boundaries: [
                boundary(.finiteAcquisitionReady, uptime: 1_000, date: 5_000),
                boundary(.observationHorizon, uptime: 60_000_001_000, date: 5_060),
            ]
        )

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.captureSessionID == session.id)
        #expect(assessment.vehicleIdentity == session.vehicleIdentity)
        #expect(assessment.status == .sufficient)
        #expect(assessment.isDurationSufficient)
        #expect(assessment.observedDurationNanoseconds == 60_000_000_000)
        #expect(assessment.readyBoundary?.recordSequenceWatermark == 0)
        #expect(assessment.horizonBoundary?.recordSequenceWatermark == 0)
        #expect(assessment.continuityBreakSequenceNumbers.isEmpty)
        #expect(session.records.isEmpty)
    }

    @Test("producer-derived assessments stay bound to the exact source capture")
    func assessmentPreservesSourceCaptureProvenance() throws {
        let boundaries = [
            boundary(.finiteAcquisitionReady, uptime: 1_000, date: 5_000),
            boundary(.observationHorizon, uptime: 60_000_001_000, date: 5_060),
        ]
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000364")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000365")!
        let firstSession = try makeSession(
            id: firstID,
            vehicleIdentity: es80,
            boundaries: boundaries
        )
        let secondSession = try makeSession(
            id: secondID,
            vehicleIdentity: deferredMaxshot,
            boundaries: boundaries
        )

        let firstAssessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: firstSession,
            minimumDurationNanoseconds: 60_000_000_000
        )
        let secondAssessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: secondSession,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(firstAssessment.status == .sufficient)
        #expect(secondAssessment.status == .sufficient)
        #expect(firstAssessment.captureSessionID == firstID)
        #expect(secondAssessment.captureSessionID == secondID)
        #expect(firstAssessment.vehicleIdentity == es80)
        #expect(secondAssessment.vehicleIdentity == deferredMaxshot)
        #expect(firstAssessment != secondAssessment)
    }

    @Test("sub-threshold interval fails closed")
    func shortIntervalIsInsufficient() throws {
        let session = try makeSession(
            boundaries: [
                boundary(.finiteAcquisitionReady, uptime: 100, date: 6_000),
                boundary(.observationHorizon, uptime: 59_000_000_100, date: 6_059),
            ]
        )

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .insufficientDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedDurationNanoseconds == 59_000_000_000)
    }

    @Test("duplicate ready boundaries are ambiguous instead of silently choosing one")
    func duplicateReadyFailsClosed() throws {
        let firstReady = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 7_000)
        let secondReady = boundary(.finiteAcquisitionReady, uptime: 55_000_001_000, date: 7_055)
        let horizon = boundary(.observationHorizon, uptime: 60_000_001_000, date: 7_060)
        let session = try makeSession(boundaries: [firstReady, secondReady, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .ambiguousFiniteAcquisitionReady)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.readyBoundary == nil)
        #expect(assessment.horizonBoundary == horizon)
        #expect(assessment.observedDurationNanoseconds == nil)
    }

    @Test("horizon without ready evidence fails closed")
    func missingReadyFailsClosed() throws {
        let horizon = boundary(.observationHorizon, uptime: 60_000_000_000, date: 8_060)
        let session = try makeSession(boundaries: [horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .missingFiniteAcquisitionReady)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.readyBoundary == nil)
        #expect(assessment.horizonBoundary == horizon)
        #expect(assessment.observedDurationNanoseconds == nil)
    }

    @Test("missing horizon evidence fails closed")
    func missingHorizonFailsClosed() throws {
        let ready = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 9_000)
        let session = try makeSession(boundaries: [ready])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .missingObservationHorizon)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.readyBoundary == ready)
        #expect(assessment.horizonBoundary == nil)
        #expect(assessment.observedDurationNanoseconds == nil)
    }

    @Test("known byte-continuity break inside the interval blocks sufficiency")
    func continuityBreakInsideWindowFailsClosed() throws {
        let interruption = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 30_000_000_000,
            receivedAtDate: Date(timeIntervalSince1970: 10_030),
            event: .interruption(
                try PassiveBluetoothCaptureInterruption(reason: "GATT invalidated; reacquisition required")
            )
        )
        let ready = boundary(.finiteAcquisitionReady, watermark: 0, uptime: 1_000, date: 10_000)
        let horizon = boundary(
            .observationHorizon,
            watermark: 1,
            uptime: 60_000_001_000,
            date: 10_060
        )
        let session = try makeSession(records: [interruption], boundaries: [ready, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .continuityBreakWithinWindow)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedDurationNanoseconds == 60_000_000_000)
        #expect(assessment.continuityBreakSequenceNumbers == [1])
    }

    @Test("continuity break already sealed before ready does not poison the new interval")
    func priorContinuityBreakIsOutsideWindow() throws {
        let priorInterruption = PassiveBluetoothCaptureRecord(
            sequenceNumber: 1,
            receivedAtUptimeNanoseconds: 500,
            receivedAtDate: Date(timeIntervalSince1970: 11_000),
            event: .interruption(try PassiveBluetoothCaptureInterruption(reason: "prior capture gap"))
        )
        let ready = boundary(.finiteAcquisitionReady, watermark: 1, uptime: 1_000, date: 11_001)
        let horizon = boundary(
            .observationHorizon,
            watermark: 1,
            uptime: 60_000_001_000,
            date: 11_061
        )
        let session = try makeSession(records: [priorInterruption], boundaries: [ready, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .sufficient)
        #expect(assessment.isDurationSufficient)
        #expect(assessment.continuityBreakSequenceNumbers.isEmpty)
    }

    @Test("zero minimum cannot accidentally disable the gate")
    func zeroMinimumFailsClosed() throws {
        let ready = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 12_000)
        let horizon = boundary(.observationHorizon, uptime: 2_000, date: 12_001)
        let session = try makeSession(boundaries: [ready, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 0
        )

        #expect(assessment.captureSessionID == session.id)
        #expect(assessment.vehicleIdentity == session.vehicleIdentity)
        #expect(assessment.status == .invalidMinimumDuration)
        #expect(!assessment.isDurationSufficient)
        #expect(assessment.observedDurationNanoseconds == nil)
        #expect(assessment.readyBoundary == ready)
        #expect(assessment.horizonBoundary == horizon)
    }

    @Test("wall-clock movement cannot manufacture or erase monotonic duration")
    func wallClockIsNotDurationAuthority() throws {
        let session = try makeSession(
            boundaries: [
                boundary(.finiteAcquisitionReady, uptime: 10_000, date: 20_000),
                boundary(.observationHorizon, uptime: 60_000_010_000, date: 19_000),
            ]
        )

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .sufficient)
        #expect(assessment.isDurationSufficient)
        #expect(assessment.observedDurationNanoseconds == 60_000_000_000)
    }

    private func makeSession(
        id: UUID? = nil,
        vehicleIdentity: VehicleIdentity? = nil,
        records: [PassiveBluetoothCaptureRecord] = [],
        boundaries: [PassiveBluetoothObservationBoundary]
    ) throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: id ?? defaultSessionID,
            vehicleIdentity: vehicleIdentity ?? es80,
            startedAt: Date(timeIntervalSince1970: 4_000),
            records: records,
            observationBoundaries: boundaries
        )
    }

    private func boundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        watermark: UInt64 = 0,
        uptime: UInt64,
        date: TimeInterval
    ) -> PassiveBluetoothObservationBoundary {
        PassiveBluetoothObservationBoundary(
            kind: kind,
            recordSequenceWatermark: watermark,
            observedAtUptimeNanoseconds: uptime,
            observedAtDate: Date(timeIntervalSince1970: date)
        )
    }
}
