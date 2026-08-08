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

        #expect(assessment.status == .sufficient)
        #expect(assessment.isSufficient)
        #expect(assessment.observedDurationNanoseconds == 60_000_000_000)
        #expect(assessment.readyBoundary?.recordSequenceWatermark == 0)
        #expect(assessment.horizonBoundary?.recordSequenceWatermark == 0)
        #expect(session.records.isEmpty)
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
        #expect(!assessment.isSufficient)
        #expect(assessment.observedDurationNanoseconds == 59_000_000_000)
    }

    @Test("latest ready boundary conservatively resets the duration window")
    func latestReadyBoundaryWins() throws {
        let firstReady = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 7_000)
        let latestReady = boundary(.finiteAcquisitionReady, uptime: 55_000_001_000, date: 7_055)
        let horizon = boundary(.observationHorizon, uptime: 60_000_001_000, date: 7_060)
        let session = try makeSession(boundaries: [firstReady, latestReady, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .insufficientDuration)
        #expect(assessment.readyBoundary == latestReady)
        #expect(assessment.horizonBoundary == horizon)
        #expect(assessment.observedDurationNanoseconds == 5_000_000_000)
    }

    @Test("missing ready evidence is reported explicitly")
    func missingReadyFailsClosed() throws {
        let horizon = boundary(.observationHorizon, uptime: 60_000_000_000, date: 8_060)
        let session = try makeSession(boundaries: [horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .missingFiniteAcquisitionReady)
        #expect(!assessment.isSufficient)
        #expect(assessment.readyBoundary == nil)
        #expect(assessment.horizonBoundary == horizon)
        #expect(assessment.observedDurationNanoseconds == nil)
    }

    @Test("missing horizon evidence is reported explicitly")
    func missingHorizonFailsClosed() throws {
        let ready = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 9_000)
        let session = try makeSession(boundaries: [ready])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 60_000_000_000
        )

        #expect(assessment.status == .missingObservationHorizon)
        #expect(!assessment.isSufficient)
        #expect(assessment.readyBoundary == ready)
        #expect(assessment.horizonBoundary == nil)
        #expect(assessment.observedDurationNanoseconds == nil)
    }

    @Test("zero minimum cannot accidentally disable the gate")
    func zeroMinimumFailsClosed() throws {
        let ready = boundary(.finiteAcquisitionReady, uptime: 1_000, date: 10_000)
        let horizon = boundary(.observationHorizon, uptime: 2_000, date: 10_001)
        let session = try makeSession(boundaries: [ready, horizon])

        let assessment = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: session,
            minimumDurationNanoseconds: 0
        )

        #expect(assessment.status == .invalidMinimumDuration)
        #expect(!assessment.isSufficient)
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
        #expect(assessment.observedDurationNanoseconds == 60_000_000_000)
    }

    private func makeSession(
        boundaries: [PassiveBluetoothObservationBoundary]
    ) throws -> PassiveBluetoothCaptureSession {
        try PassiveBluetoothCaptureSession(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000363")!,
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 4_000),
            observationBoundaries: boundaries
        )
    }

    private func boundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        uptime: UInt64,
        date: TimeInterval
    ) -> PassiveBluetoothObservationBoundary {
        PassiveBluetoothObservationBoundary(
            kind: kind,
            recordSequenceWatermark: 0,
            observedAtUptimeNanoseconds: uptime,
            observedAtDate: Date(timeIntervalSince1970: date)
        )
    }
}
