import Foundation
import Testing
@testable import NembraCore

@Suite("Automatic ride capture readiness")
struct AutomaticRideCaptureReadinessTests {
    private let peripheralID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    private func input(
        enabled: Bool = true,
        accessoryAuthorization: AccessorySetupAuthorizationEvidence = .authorized,
        descriptor: AccessorySetupDescriptorEvidence = .captureVerified(provenanceID: "capture-artifact-13"),
        authorizedPeripheralID: UUID? = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        bluetoothAuthorization: AutomaticCaptureBluetoothAuthorization = .allowed,
        bluetoothRadio: AutomaticCaptureBluetoothRadioState = .poweredOn,
        backgroundService: AutomaticCaptureBackgroundServiceEvidence = .available,
        location: AutomaticCaptureLocationAuthorization = .always,
        backgroundLocation: AutomaticCaptureBackgroundLocationSessionEvidence = .configured,
        firstUnlock: Bool = true,
        forceQuitRequiresReopen: Bool = false,
        storage: AutomaticCaptureStorageEvidence = .writableAndVerified
    ) -> AutomaticRideCaptureReadinessInput {
        AutomaticRideCaptureReadinessInput(
            isAutomaticCaptureEnabled: enabled,
            relaunchPolicy: .accessorySetupKitRequired,
            accessorySetupAuthorization: accessoryAuthorization,
            accessorySetupDescriptor: descriptor,
            knownAccessory: AutomaticCaptureKnownAccessoryEvidence(
                knownPeripheralIdentifier: peripheralID,
                authorizedAccessoryPeripheralIdentifier: authorizedPeripheralID
            ),
            bluetoothAuthorization: bluetoothAuthorization,
            bluetoothRadioState: bluetoothRadio,
            restorationConfiguration: AutomaticCaptureRestorationConfigurationEvidence(
                persistedCentralRestorationIdentifier: "com.nembra.central.restoration",
                bluetoothCentralBackgroundModeDeclared: true,
                restorationHandlerInstalledBeforeOrdinaryInitialization: true,
                pendingWork: .knownPeripheralConnectionOrSubscription
            ),
            backgroundService: backgroundService,
            locationAuthorization: location,
            backgroundLocationSession: backgroundLocation,
            lifecycle: AutomaticCaptureLifecycleEvidence(
                hasCompletedFirstUnlockAfterDeviceRestart: firstUnlock,
                requiresForegroundReopenAfterManualForceQuit: forceQuitRequiresReopen
            ),
            storage: storage
        )
    }

    @Test("fully evidenced setup is eligible but still carries best-effort OS truth")
    func ready() {
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(input())

        #expect(result.status == .ready)
        #expect(result.canCaptureRideTelemetryWithoutOpeningApp)
        #expect(result.canCaptureRoadCoverageWithoutOpeningApp)
        #expect(result.issues.isEmpty)
        #expect(result.deliveryExpectation == .bestEffortSubjectToSystemSchedulingAndLifecycle)
    }

    @Test("location-limited setup can capture telemetry without claiming road coverage")
    func locationLimitedTelemetry() {
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(
            input(location: .whileInUse, backgroundLocation: .notConfigured)
        )

        #expect(result.status == .locationLimited)
        #expect(result.canCaptureRideTelemetryWithoutOpeningApp)
        #expect(!result.canCaptureRoadCoverageWithoutOpeningApp)
        #expect(result.issues == [.locationOnlyWhileInUse])
    }

    @Test("force quit and pre-first-unlock state are explicit blockers")
    func forceQuitAndFirstUnlock() {
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(
            input(firstUnlock: false, forceQuitRequiresReopen: true)
        )

        #expect(result.status == .actionRequired)
        #expect(!result.canCaptureRideTelemetryWithoutOpeningApp)
        #expect(!result.canCaptureRoadCoverageWithoutOpeningApp)
        #expect(result.issues.contains(.deviceRestartAwaitingFirstUnlock))
        #expect(result.issues.contains(.foregroundReopenRequiredAfterManualForceQuit))
    }

    @Test("disabled is intentional, not reported as a permission failure soup")
    func disabled() {
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(
            input(
                enabled: false,
                accessoryAuthorization: .denied,
                bluetoothRadio: .poweredOff,
                firstUnlock: false,
                storage: .lastWriteFailed
            )
        )

        #expect(result.status == .intentionallyDisabled)
        #expect(result.issues == [.intentionallyDisabled])
        #expect(!result.canCaptureRideTelemetryWithoutOpeningApp)
        #expect(!result.canCaptureRoadCoverageWithoutOpeningApp)
    }

    @Test("authorization cannot substitute for verified descriptor and exact identity custody")
    func accessoryEvidenceMustBeExact() {
        let anotherPeripheral = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(
            input(
                descriptor: .unverified,
                authorizedPeripheralID: anotherPeripheral
            )
        )

        #expect(result.status == .actionRequired)
        #expect(result.issues.contains(.accessoryDescriptorUnverified))
        #expect(result.issues.contains(.authorizedAccessoryIdentityMismatch))
        #expect(!result.canCaptureRideTelemetryWithoutOpeningApp)
    }

    @Test("storage write failure fails closed before packet-derived truth")
    func storageFailure() {
        let result = AutomaticRideCaptureReadinessEvaluator.evaluate(
            input(storage: .lastWriteFailed)
        )

        #expect(result.status == .actionRequired)
        #expect(result.issues.contains(.storageWriteFailed))
        #expect(!result.canCaptureRideTelemetryWithoutOpeningApp)
    }
}

@Suite("Automatic ride phase projection")
struct AutomaticRideCapturePhaseProjectionTests {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func session() -> ActiveRideSession {
        ActiveRideSession(
            id: sessionID,
            beganAtUptimeNanoseconds: 10,
            beganAtDate: epoch,
            confirmedAtUptimeNanoseconds: 20,
            confirmedAtDate: epoch.addingTimeInterval(1),
            startingOdometerKilometers: nil,
            latestOdometerKilometers: nil,
            accumulatedGPSDistanceMeters: 0
        )
    }

    @Test("quick reconnect keeps the RideEngine session identity")
    func quickReconnectKeepsSessionIdentity() {
        let active = session()
        let disconnected = TemporarilyDisconnectedRide(
            session: active,
            disconnectedAtUptimeNanoseconds: 30,
            disconnectedAtDate: epoch.addingTimeInterval(2)
        )

        let gap = AutomaticRideCapturePhaseProjector.project(
            rideEnginePhase: .temporarilyDisconnected(disconnected),
            candidateID: nil,
            idleProjection: .connectingOrRestoring
        )
        let resumed = AutomaticRideCapturePhaseProjector.project(
            rideEnginePhase: .active(active),
            candidateID: nil,
            idleProjection: .connectedIdle
        )

        #expect(gap == .temporaryGap(rideSessionID: sessionID))
        #expect(resumed == .active(rideSessionID: sessionID))
    }

    @Test("all idle shell phases remain projection-only")
    func idleProjection() {
        #expect(
            AutomaticRideCapturePhaseProjector.project(
                rideEnginePhase: .idle,
                candidateID: nil,
                idleProjection: .armed
            ) == .armed
        )
        #expect(
            AutomaticRideCapturePhaseProjector.project(
                rideEnginePhase: .idle,
                candidateID: nil,
                idleProjection: .connectingOrRestoring
            ) == .connectingOrRestoring
        )
        #expect(
            AutomaticRideCapturePhaseProjector.project(
                rideEnginePhase: .idle,
                candidateID: nil,
                idleProjection: .connectedIdle
            ) == .connectedIdle
        )
        #expect(
            AutomaticRideCapturePhaseProjector.project(
                rideEnginePhase: .idle,
                candidateID: nil,
                idleProjection: .closed(rideSessionID: sessionID)
            ) == .closed(rideSessionID: sessionID)
        )
    }

    @Test("candidate projection fails closed without the journal identity")
    func candidateNeedsJournalIdentity() {
        let candidate = RideCandidate(
            beganAtUptimeNanoseconds: 1,
            beganAtDate: epoch,
            startingOdometerKilometers: nil,
            latestOdometerKilometers: nil,
            accumulatedGPSDistanceMeters: 0
        )

        #expect(
            AutomaticRideCapturePhaseProjector.project(
                rideEnginePhase: .candidate(candidate),
                candidateID: nil,
                idleProjection: .connectedIdle
            ) == .needsReview
        )
    }
}

@Suite("Crash-safe automatic ride candidate evidence")
struct AutomaticRideCandidateJournalTests {
    private let wallEpoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let candidateID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let processOne = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let processTwo = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let sessionID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nembra-automatic-candidate-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func entry(
        sequence: UInt64,
        process: UUID? = nil,
        uptime: UInt64? = nil,
        odometer: Double? = 42
    ) throws -> AutomaticRideCandidateEvidenceEntry {
        let acceptedProcess = process ?? processOne
        let acceptedUptime = uptime ?? sequence * 100
        let speed = try SpeedTelemetrySample(
            source: .scooterBluetooth,
            provenance: .absoluteMeasurement,
            metersPerSecond: Double(sequence),
            receivedAtUptimeNanoseconds: acceptedUptime,
            receivedAtDate: wallEpoch.addingTimeInterval(Double(sequence))
        )
        return try AutomaticRideCandidateEvidenceEntry(
            candidateID: candidateID,
            sequence: sequence,
            processEpochID: acceptedProcess,
            receivedAtUptimeNanoseconds: acceptedUptime,
            receivedAtDate: wallEpoch.addingTimeInterval(Double(sequence)),
            connection: .connected,
            speedSample: speed,
            odometerKilometers: odometer,
            qualityScreenedGPSDistanceDeltaMeters: Double(sequence),
            motionIndicatesMovement: true
        )
    }

    private func candidatePhase(at uptime: UInt64 = 50) -> RideEnginePhase {
        .candidate(
            RideCandidate(
                beganAtUptimeNanoseconds: uptime,
                beganAtDate: wallEpoch.addingTimeInterval(10),
                startingOdometerKilometers: nil,
                latestOdometerKilometers: nil,
                accumulatedGPSDistanceMeters: 0
            )
        )
    }

    private func activePhase() -> RideEnginePhase {
        .active(
            ActiveRideSession(
                id: sessionID,
                beganAtUptimeNanoseconds: 100,
                beganAtDate: wallEpoch,
                confirmedAtUptimeNanoseconds: 200,
                confirmedAtDate: wallEpoch.addingTimeInterval(2),
                startingOdometerKilometers: 42,
                latestOdometerKilometers: 42.1,
                accumulatedGPSDistanceMeters: 5
            )
        )
    }

    @Test("identical packet replay is idempotent")
    func duplicateReplay() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)
        let first = try entry(sequence: 1)
        try await journal.append(first)
        let replay = try await journal.append(first)

        guard case let .duplicateReplay(snapshot) = replay else {
            Issue.record("Expected duplicate replay")
            return
        }
        #expect(snapshot.entries == [first])
    }

    @Test("same sequence with different evidence is rejected")
    func conflictingReplay() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)
        try await journal.append(try entry(sequence: 1, odometer: 42))

        await #expect(throws: AutomaticRideCandidateJournalError.conflictingReplay(sequence: 1)) {
            try await journal.append(try entry(sequence: 1, odometer: 43))
        }
    }

    @Test("truncated newest atomic slot falls back to its known-good predecessor")
    func truncatedNewestFallback() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch) // A1
        let first = try entry(sequence: 1)
        try await journal.append(first) // B2
        try await journal.append(try entry(sequence: 2)) // A3

        let newestSlot = dir.appendingPathComponent(
            AtomicAutomaticRideCandidateJournal.slotAFileName
        )
        try Data("truncated".utf8).write(to: newestSlot)

        let restarted = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        let restored = try await restarted.restore()
        #expect(restored.disposition == .collectingInCurrentProcess)
        #expect(restored.snapshot?.entries == [first])
        #expect(restored.observationsForCurrentProcess.count == 1)
    }

    @Test("promotion freezes the exact RideEngine session and replay is idempotent")
    func promotionUsesRideEngineSession() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)
        try await journal.append(try entry(sequence: 1))

        let promoted = try await journal.promote(
            candidateID: candidateID,
            using: activePhase(),
            atDate: wallEpoch.addingTimeInterval(3)
        )
        guard case let .changed(snapshot) = promoted else {
            Issue.record("Expected first promotion to mutate")
            return
        }
        #expect(snapshot.promotedRideSessionID == sessionID)

        let replay = try await journal.promote(
            candidateID: candidateID,
            using: activePhase(),
            atDate: wallEpoch.addingTimeInterval(4)
        )
        guard case .duplicateReplay = replay else {
            Issue.record("Expected idempotent promotion replay")
            return
        }

        let restored = try await journal.restore()
        #expect(restored.disposition == .promoted(rideSessionID: sessionID))
        #expect(restored.observationsForCurrentProcess.isEmpty)
    }

    @Test("interrupted candidate never reuses prior-process uptime or auto-promotes")
    func interruptedRestoreRequiresFreshEngineCandidate() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let firstProcessJournal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await firstProcessJournal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)
        try await firstProcessJournal.append(try entry(sequence: 1, uptime: 9_000))

        let restarted = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processTwo
        )
        let restored = try await restarted.restore()
        #expect(restored.disposition == .interruptedAwaitingFreshEvidence)
        #expect(restored.observationsForCurrentProcess.isEmpty)
        #expect(restored.snapshot?.status == .interruptedAwaitingFreshEvidence)

        await #expect(throws: AutomaticRideCandidateJournalError.invalidTransition) {
            try await restarted.promote(
                candidateID: candidateID,
                using: activePhase(),
                atDate: wallEpoch.addingTimeInterval(11)
            )
        }

        // A smaller uptime is valid in the new epoch and is never compared with
        // the previous process's 9,000-nanosecond value.
        try await restarted.append(
            try entry(sequence: 2, process: processTwo, uptime: 50)
        )
        try await restarted.resumeInterruptedCandidate(
            candidateID: candidateID,
            after: candidatePhase(at: 50),
            atDate: wallEpoch.addingTimeInterval(12)
        )
        let promoted = try await restarted.promote(
            candidateID: candidateID,
            using: activePhase(),
            atDate: wallEpoch.addingTimeInterval(13)
        )

        guard case let .changed(snapshot) = promoted else {
            Issue.record("Expected explicit current-process promotion")
            return
        }
        #expect(snapshot.promotedRideSessionID == sessionID)
        #expect(snapshot.entries.map(\.processEpochID) == [processOne, processTwo])
    }

    @Test("foreign-process entries cannot be appended through a current journal")
    func foreignProcessAppendRejected() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)

        await #expect(throws: AutomaticRideCandidateJournalError.foreignProcessEpoch) {
            try await journal.append(try entry(sequence: 1, process: processTwo))
        }
    }

    @Test("retirement preserves promoted custody and permits the next candidate")
    func retirementAndNextCandidate() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = AtomicAutomaticRideCandidateJournal(
            directoryURL: dir,
            processEpochID: processOne
        )
        try await journal.beginCandidate(candidateID: candidateID, beganAtDate: wallEpoch)
        try await journal.append(try entry(sequence: 1))
        try await journal.promote(
            candidateID: candidateID,
            using: activePhase(),
            atDate: wallEpoch.addingTimeInterval(3)
        )
        try await journal.retire(
            candidateID: candidateID,
            reason: .promotedEvidenceCommitted,
            atDate: wallEpoch.addingTimeInterval(4)
        )

        let nextCandidateID = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let next = try await journal.beginCandidate(
            candidateID: nextCandidateID,
            beganAtDate: wallEpoch.addingTimeInterval(5)
        )
        guard case let .changed(snapshot) = next else {
            Issue.record("Expected retired journal to accept the next candidate")
            return
        }
        #expect(snapshot.candidateID == nextCandidateID)
        #expect(snapshot.entries.isEmpty)
        #expect(snapshot.status == .collecting)
    }
}
