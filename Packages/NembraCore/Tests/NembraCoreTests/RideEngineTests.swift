import Foundation
import Testing
@testable import NembraCore

@Suite("Automatic ride engine")
struct RideEngineTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func policy(
        confirmationDuration: UInt64 = 2_000,
        endingDuration: UInt64 = 5_000,
        maximumSpeedSampleAge: UInt64 = 1_000
    ) throws -> RideDetectionPolicy {
        try RideDetectionPolicy(
            candidateSpeedKilometersPerHour: 1,
            confirmationSpeedKilometersPerHour: 4,
            confirmationDurationNanoseconds: confirmationDuration,
            confirmationOdometerDeltaKilometers: 0.05,
            confirmationGPSDistanceMeters: 8,
            endingDurationNanoseconds: endingDuration,
            maximumSpeedSampleAgeNanoseconds: maximumSpeedSampleAge
        )
    }

    private func date(at uptimeNanoseconds: UInt64) -> Date {
        epoch.addingTimeInterval(Double(uptimeNanoseconds) / 1_000_000_000)
    }

    private func speed(
        _ kph: Double,
        receivedAt t: UInt64,
        source: SpeedTelemetrySource = .scooterBluetooth
    ) throws -> SpeedTelemetrySample {
        let provenance: SpeedTelemetryProvenance = source == .motionAssist
            ? .shortHorizonEstimate
            : .absoluteMeasurement
        return try SpeedTelemetrySample(
            source: source,
            provenance: provenance,
            metersPerSecond: kph / 3.6,
            receivedAtUptimeNanoseconds: t,
            receivedAtDate: date(at: t)
        )
    }

    private func observation(
        _ t: UInt64,
        connection: VehicleConnectionState = .connected,
        speedKPH: Double? = nil,
        speedReceivedAt: UInt64? = nil,
        speedSource: SpeedTelemetrySource = .scooterBluetooth,
        odometer: Double? = nil,
        gpsDelta: Double? = nil,
        motion: Bool = false
    ) throws -> RideObservation {
        let sample = try speedKPH.map {
            try speed($0, receivedAt: speedReceivedAt ?? t, source: speedSource)
        }
        return try RideObservation(
            receivedAtUptimeNanoseconds: t,
            receivedAtDate: date(at: t),
            connection: connection,
            speedSample: sample,
            odometerKilometers: odometer,
            qualityScreenedGPSDistanceDeltaMeters: gpsDelta,
            motionIndicatesMovement: motion
        )
    }

    @Test("a tiny motion blip becomes a candidate then cancels, not a ride")
    func tinyMovementDoesNotCreateRide() throws {
        var engine = RideEngine(policy: try policy())
        let first = try engine.ingest(observation(1_000, motion: true))
        #expect(first.events == [.candidateStarted])
        guard case .candidate = first.phase else {
            Issue.record("expected candidate phase")
            return
        }

        let second = try engine.ingest(observation(1_500))
        #expect(second.phase == .idle)
        #expect(second.events == [.candidateCancelled])
    }

    @Test("disconnect during an unconfirmed candidate cancels it instead of creating a ride")
    func candidateDisconnectCancels() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, motion: true))
        let update = try engine.ingest(observation(1_500, connection: .disconnected, motion: true))
        #expect(update.phase == .idle)
        #expect(update.events == [.candidateCancelled])
    }

    @Test("sustained authoritative speed confirms a ride after injected duration")
    func sustainedSpeedConfirmsRide() throws {
        let fixedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var engine = RideEngine(policy: try policy(), makeSessionID: { fixedID })
        _ = try engine.ingest(observation(1_000, speedKPH: 5, odometer: 143.2))
        let stillCandidate = try engine.ingest(observation(2_500, speedKPH: 6, odometer: 143.21))
        guard case .candidate = stillCandidate.phase else {
            Issue.record("ride confirmed before policy duration")
            return
        }

        let confirmed = try engine.ingest(observation(3_000, speedKPH: 7, odometer: 143.23))
        guard case let .active(session) = confirmed.phase else {
            Issue.record("expected active ride")
            return
        }
        #expect(session.id == fixedID)
        #expect(session.beganAtUptimeNanoseconds == 1_000)
        #expect(session.confirmedAtUptimeNanoseconds == 3_000)
        #expect(session.startingOdometerKilometers == 143.2)
        #expect(confirmed.events == [.rideStarted(session)])
    }

    @Test("motion assist can wake candidate but cannot confirm absolute vehicle movement")
    func motionAssistCannotConfirmRide() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, speedKPH: 6, speedSource: .motionAssist, motion: true))
        let update = try engine.ingest(observation(4_000, speedKPH: 8, speedSource: .motionAssist, motion: true))
        guard case .candidate = update.phase else {
            Issue.record("motion-only estimate must not confirm ride")
            return
        }
        #expect(!update.events.contains { if case .rideStarted = $0 { true } else { false } })
    }

    @Test("stale authoritative speed cannot wake a ride candidate")
    func staleSpeedCannotStartCandidate() throws {
        var engine = RideEngine(policy: try policy(maximumSpeedSampleAge: 500))
        let update = try engine.ingest(
            observation(2_000, speedKPH: 20, speedReceivedAt: 1_000)
        )
        #expect(update.phase == .idle)
        #expect(update.events.isEmpty)
    }

    @Test("stale authoritative speed cannot keep an active ride alive")
    func staleSpeedCannotSustainActiveRide() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, maximumSpeedSampleAge: 500))
        _ = try engine.ingest(observation(1_000, speedKPH: 8))
        let update = try engine.ingest(
            observation(2_000, speedKPH: 8, speedReceivedAt: 1_000)
        )
        guard case .endingCandidate = update.phase else {
            Issue.record("stale speed must not masquerade as current movement")
            return
        }
    }

    @Test("stale authoritative speed cannot confirm a motion-started candidate")
    func staleSpeedCannotConfirmCandidate() throws {
        var engine = RideEngine(policy: try policy(maximumSpeedSampleAge: 500))
        _ = try engine.ingest(observation(1_000, motion: true))
        let update = try engine.ingest(
            observation(3_000, speedKPH: 20, speedReceivedAt: 1_000, motion: true)
        )
        guard case .candidate = update.phase else {
            Issue.record("stale absolute speed must not confirm a candidate")
            return
        }
    }

    @Test("speed exactly at the injected freshness boundary remains eligible")
    func speedAtFreshnessBoundaryIsAccepted() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, maximumSpeedSampleAge: 500))
        let update = try engine.ingest(
            observation(1_000, speedKPH: 8, speedReceivedAt: 500)
        )
        guard case .active = update.phase else {
            Issue.record("sample at maximum allowed age should remain eligible")
            return
        }
    }

    @Test("odometer movement can confirm when live speed is missing")
    func odometerCanConfirmRide() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, odometer: 100, motion: true))
        let update = try engine.ingest(observation(3_000, odometer: 100.06, motion: true))
        guard case .active = update.phase else {
            Issue.record("verified odometer delta should confirm ride")
            return
        }
    }

    @Test("a candidate can establish its odometer baseline after candidate start")
    func lateCandidateOdometerBaselineCanConfirm() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, motion: true))

        let baseline = try engine.ingest(observation(1_500, odometer: 100, motion: true))
        guard case let .candidate(candidate) = baseline.phase else {
            Issue.record("expected candidate after first ODO baseline")
            return
        }
        #expect(candidate.startingOdometerKilometers == 100)
        #expect(candidate.latestOdometerKilometers == 100)

        let update = try engine.ingest(observation(3_000, odometer: 100.06, motion: true))
        guard case let .active(session) = update.phase else {
            Issue.record("ODO observed after candidate start should still be usable")
            return
        }
        #expect(session.startingOdometerKilometers == 100)
        #expect(abs((session.latestOdometerKilometers ?? 0) - 100.06) < 0.000_001)
    }

    @Test("quality-screened GPS distance accumulates across the candidate window")
    func gpsCanConfirmRide() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, gpsDelta: 3))
        let update = try engine.ingest(observation(3_000, gpsDelta: 5))
        guard case let .active(session) = update.phase else {
            Issue.record("cumulative quality-screened GPS evidence should confirm ride")
            return
        }
        #expect(session.accumulatedGPSDistanceMeters == 8)
    }

    @Test("odometer movement keeps an active ride alive when speed packets are missing")
    func odometerKeepsActiveRideAlive() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 20))
        let update = try engine.ingest(observation(2_000, odometer: 20.01))
        guard case .active = update.phase else {
            Issue.record("increasing ODO is movement evidence, not a stop")
            return
        }
        #expect(update.events.isEmpty)
    }

    @Test("quality-screened GPS movement keeps an active ride alive when BLE speed is absent")
    func gpsKeepsActiveRideAlive() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        _ = try engine.ingest(observation(1_000, speedKPH: 8))
        let update = try engine.ingest(observation(2_000, gpsDelta: 1.5))
        guard case let .active(session) = update.phase else {
            Issue.record("screened GPS route movement should keep the same ride active")
            return
        }
        #expect(session.accumulatedGPSDistanceMeters == 1.5)
    }

    @Test("disconnect during active ride preserves the same session and evidence")
    func activeDisconnectPreservesSession() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 20, gpsDelta: 2))
        guard case let .active(started) = start.phase else {
            Issue.record("expected immediate active ride")
            return
        }

        let lost = try engine.ingest(
            observation(2_000, connection: .disconnected, odometer: 20.02, gpsDelta: 1)
        )
        guard case let .temporarilyDisconnected(disconnected) = lost.phase else {
            Issue.record("expected temporary disconnect")
            return
        }
        #expect(disconnected.session.id == started.id)
        #expect(disconnected.session.latestOdometerKilometers == 20.02)
        #expect(disconnected.session.accumulatedGPSDistanceMeters == 3)
    }

    @Test("reconnect with live speed resumes the same ride")
    func reconnectResumesRide() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8))
        guard case let .active(started) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, connection: .disconnected))
        let resumed = try engine.ingest(observation(3_000, speedKPH: 6))
        guard case let .active(session) = resumed.phase else {
            Issue.record("expected resumed active ride")
            return
        }
        #expect(session.id == started.id)
        #expect(resumed.events == [.rideResumed(started.id)])
    }

    @Test("reconnect with only new odometer movement resumes the same ride")
    func reconnectWithOdometerMovementResumesRide() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 20))
        guard case let .active(started) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, connection: .disconnected, odometer: 20))
        let resumed = try engine.ingest(observation(3_000, odometer: 20.01))
        guard case let .active(session) = resumed.phase else {
            Issue.record("new ODO evidence on reconnect should resume the same ride")
            return
        }
        #expect(session.id == started.id)
        #expect(resumed.events == [.rideResumed(started.id)])
    }

    @Test("stationary reconnect enters ending candidate without claiming ride resumed")
    func stationaryReconnectDoesNotClaimResume() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8))
        guard case let .active(session) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, connection: .disconnected))
        let reconnect = try engine.ingest(observation(3_000, speedKPH: 0))
        guard case .endingCandidate = reconnect.phase else {
            Issue.record("stationary reconnect should begin end confirmation")
            return
        }
        #expect(reconnect.events == [.endingCandidateStarted(session.id)])
    }

    @Test("stopping must remain stationary for ending policy duration")
    func endingCandidateRequiresDuration() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, endingDuration: 5_000))
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 50))
        _ = try engine.ingest(observation(1_500, speedKPH: 8, odometer: 50.1))
        let ending = try engine.ingest(observation(2_000, speedKPH: 0, odometer: 50.1))
        guard case .endingCandidate = ending.phase else {
            Issue.record("expected ending candidate")
            return
        }

        let notYet = try engine.ingest(observation(6_999, speedKPH: 0, odometer: 50.1))
        guard case .endingCandidate = notYet.phase else {
            Issue.record("ride ended before stop duration")
            return
        }

        let ended = try engine.ingest(observation(7_000, speedKPH: 0, odometer: 50.1))
        #expect(ended.phase == .idle)
        guard case let .rideEnded(evidence) = ended.events.first else {
            Issue.record("expected ride-ended evidence")
            return
        }
        #expect(abs((evidence.odometerDeltaKilometers ?? 0) - 0.1) < 0.000_001)
    }

    @Test("odometer movement during ending candidate resumes instead of splitting ride")
    func odometerMovementCancelsEndingCandidate() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 20))
        guard case let .active(started) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, speedKPH: 0, odometer: 20))
        let resumed = try engine.ingest(observation(3_000, odometer: 20.01))
        guard case let .active(session) = resumed.phase else {
            Issue.record("new ODO movement should cancel ride ending")
            return
        }
        #expect(session.id == started.id)
        #expect(resumed.events == [.rideResumed(started.id)])
    }

    @Test("live speed returning during ending candidate resumes instead of splitting ride")
    func speedMovementCancelsEndingCandidate() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        let start = try engine.ingest(observation(1_000, speedKPH: 8))
        guard case let .active(started) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, speedKPH: 0))
        let resumed = try engine.ingest(observation(3_000, speedKPH: 4))
        guard case let .active(session) = resumed.phase else {
            Issue.record("expected active ride")
            return
        }
        #expect(session.id == started.id)
        #expect(resumed.events == [.rideResumed(started.id)])
    }

    @Test("disconnect alone never finalizes a confirmed ride")
    func disconnectNeverEndsByItself() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, endingDuration: 1))
        let start = try engine.ingest(observation(1_000, speedKPH: 8))
        guard case let .active(started) = start.phase else { return }
        _ = try engine.ingest(observation(2_000, connection: .disconnected))
        let muchLater = try engine.ingest(observation(1_000_000, connection: .disconnected))
        guard case let .temporarilyDisconnected(disconnected) = muchLater.phase else {
            Issue.record("disconnect must preserve session for later reconciliation")
            return
        }
        #expect(disconnected.session.id == started.id)
        #expect(muchLater.events.isEmpty)
    }

    @Test("completed ride preserves accumulated screened GPS evidence")
    func completedRideCarriesGPSEvidence() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, endingDuration: 5_000))
        _ = try engine.ingest(observation(1_000, speedKPH: 8, gpsDelta: 2))
        _ = try engine.ingest(observation(2_000, gpsDelta: 3))
        _ = try engine.ingest(observation(3_000, speedKPH: 0))
        let ended = try engine.ingest(observation(8_000, speedKPH: 0))

        guard case let .rideEnded(evidence) = ended.events.first else {
            Issue.record("expected completed evidence")
            return
        }
        #expect(evidence.qualityScreenedGPSDistanceMeters == 5)
    }

    @Test("first odometer observed after ride confirmation becomes an honest late baseline")
    func lateActiveOdometerBaselineIsNotBackdated() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0, endingDuration: 5_000))
        _ = try engine.ingest(observation(1_000, speedKPH: 8))

        let baseline = try engine.ingest(observation(2_000, speedKPH: 8, odometer: 100))
        guard case let .active(sessionAtBaseline) = baseline.phase else { return }
        #expect(sessionAtBaseline.startingOdometerKilometers == 100)
        #expect(sessionAtBaseline.latestOdometerKilometers == 100)

        _ = try engine.ingest(observation(3_000, odometer: 100.04))
        _ = try engine.ingest(observation(4_000, speedKPH: 0, odometer: 100.04))
        let ended = try engine.ingest(observation(9_000, speedKPH: 0, odometer: 100.04))
        guard case let .rideEnded(evidence) = ended.events.first else { return }
        #expect(abs((evidence.odometerDeltaKilometers ?? 0) - 0.04) < 0.000_001)
    }

    @Test("odometer regressions never reduce confirmed ride evidence")
    func odometerRegressionIsIgnored() throws {
        var engine = RideEngine(policy: try policy(confirmationDuration: 0))
        _ = try engine.ingest(observation(1_000, speedKPH: 8, odometer: 100))
        let forward = try engine.ingest(observation(2_000, speedKPH: 8, odometer: 100.2))
        guard case let .active(forwardSession) = forward.phase else { return }
        #expect(forwardSession.latestOdometerKilometers == 100.2)

        let regressed = try engine.ingest(observation(3_000, speedKPH: 8, odometer: 99.9))
        guard case let .active(regressedSession) = regressed.phase else { return }
        #expect(regressedSession.latestOdometerKilometers == 100.2)
    }

    @Test("GPS accumulation overflow is rejected transactionally")
    func gpsOverflowDoesNotMutateEngine() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(1_000, gpsDelta: Double.greatestFiniteMagnitude))
        let phaseBefore = engine.phase

        #expect(throws: RideEngineError.invalidObservation) {
            _ = try engine.ingest(observation(1_500, gpsDelta: Double.greatestFiniteMagnitude))
        }
        #expect(engine.phase == phaseBefore)

        // Reusing the rejected timestamp proves the failed observation did not
        // advance the engine's monotonic clock either.
        let retry = try engine.ingest(observation(1_500, gpsDelta: 0))
        guard case .candidate = retry.phase else {
            Issue.record("valid retry at rejected timestamp should still be accepted")
            return
        }
    }

    @Test("out-of-order observations are rejected without changing phase or clock")
    func nonMonotonicObservationRejected() throws {
        var engine = RideEngine(policy: try policy())
        _ = try engine.ingest(observation(2_000, motion: true))
        let phaseBefore = engine.phase
        #expect(throws: RideEngineError.nonMonotonicObservation) {
            _ = try engine.ingest(observation(1_999, motion: true))
        }
        #expect(engine.phase == phaseBefore)

        let validNext = try engine.ingest(observation(2_001, motion: true))
        guard case .candidate = validNext.phase else {
            Issue.record("failed older observation must not poison later ordering")
            return
        }
    }

    @Test("invalid policy and invalid observations are rejected")
    func invalidInputsRejected() throws {
        #expect(throws: RideEngineError.invalidPolicy) {
            _ = try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 5,
                confirmationSpeedKilometersPerHour: 4,
                confirmationDurationNanoseconds: 0,
                confirmationOdometerDeltaKilometers: 0.05,
                confirmationGPSDistanceMeters: 8,
                endingDurationNanoseconds: 5_000,
                maximumSpeedSampleAgeNanoseconds: 1_000
            )
        }
        #expect(throws: RideEngineError.invalidPolicy) {
            _ = try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 4,
                confirmationDurationNanoseconds: 0,
                confirmationOdometerDeltaKilometers: 0.05,
                confirmationGPSDistanceMeters: 8,
                endingDurationNanoseconds: 0,
                maximumSpeedSampleAgeNanoseconds: 1_000
            )
        }
        #expect(throws: RideEngineError.invalidPolicy) {
            _ = try RideDetectionPolicy(
                candidateSpeedKilometersPerHour: 1,
                confirmationSpeedKilometersPerHour: 4,
                confirmationDurationNanoseconds: 0,
                confirmationOdometerDeltaKilometers: 0.05,
                confirmationGPSDistanceMeters: 8,
                endingDurationNanoseconds: 5_000,
                maximumSpeedSampleAgeNanoseconds: 0
            )
        }
        #expect(throws: RideEngineError.invalidObservation) {
            _ = try RideObservation(
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: epoch,
                connection: .connected,
                odometerKilometers: -.infinity
            )
        }
        #expect(throws: RideEngineError.invalidObservation) {
            _ = try RideObservation(
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: epoch,
                connection: .connected,
                qualityScreenedGPSDistanceDeltaMeters: -1
            )
        }
        #expect(throws: RideEngineError.invalidObservation) {
            _ = try RideObservation(
                receivedAtUptimeNanoseconds: 1_000,
                receivedAtDate: epoch,
                connection: .connected,
                speedSample: try speed(5, receivedAt: 1_001)
            )
        }
        #expect(throws: RideEngineError.invalidObservation) {
            _ = try RideObservation(
                receivedAtUptimeNanoseconds: 1_000,
                receivedAtDate: Date(timeIntervalSinceReferenceDate: .infinity),
                connection: .connected
            )
        }
    }
}
